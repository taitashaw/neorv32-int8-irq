# Block design for the ZCU104: the combined system (INT8 helper + stopwatch) as one canvas.
#
#   clock_and_reset (hierarchy): zynq_ps_makes_the_clock (Zynq UltraScale+ PS, 100 MHz pl_clk0)
#                                + reset_helper (proc_sys_reset)
#   doorbell_button (push button SW0) -> doorbell_sync -> riscv_brain_with_int8_math_helper (irq)
#                                                     \-> stopwatch_latency_monitor (doorbell)
#   riscv_brain_with_int8_math_helper -- trace_valid / trace_intr --> stopwatch_latency_monitor
#   riscv_brain_with_int8_math_helper <-> address_switch <-> stopwatch_latency_monitor (0xF00000xx)
#                                                        <-> nothing_else_on_bus (every other address)
#   uart_text_out / uart_text_in = PL UART
#   leds: too_slow_led (LED 0), doorbell_led (LED 1), awake_led (LED 2), talking_led (LED 3)
#
# Module references: rtl/bd/*.vhd (plain std_logic ports; they wrap the unchanged NEORV32,
# the 2-stage INT8 CFU rtl/neorv32_cpu_alu_cfu.vhd (DOT4ACC, SETACC, GETACC) and rtl/irq_lat_mon.vhd).
# Adapted from the two source projects' scripts/build_bd.tcl.
# Run: vivado -mode batch -source scripts/build_bd.tcl   (project: build/vivado_bd)
#   BD_SYNTH=0  stop after the validated block design (default: synthesis, implementation, bitstream)
set root [file normalize [file dirname [info script]]/..]
set R    $root/neorv32
set proj $root/build/vivado_bd
set rpt  $root/build/bd_reports
file mkdir $rpt
create_project int8_irq_bd $proj -part xczu7ev-ffvc1156-2-e -force
set bp [lindex [lsort [get_board_parts -quiet *zcu104*]] end]
puts "BOARD_PART: $bp"
if {$bp ne ""} { set_property board_part $bp [current_project] }

# NEORV32 (unchanged), the 2-stage INT8 CFU swapped in through the file list,
# the program image used for the out-of-context runs, and the monitor
set cfu $root/rtl/neorv32_cpu_alu_cfu.vhd
set img $root/impl/imem_image_for_impl.vhd
set fl {}
set fp [open $R/rtl/file_list_core.f r]
foreach l [split [read $fp] "\n"] {
  set l [string trim $l]
  if {$l eq ""} continue
  set f [string map [list {$NEORV32_HOME} $R] $l]
  if {[string match *neorv32_imem_image.vhd $f]}  { set f $img }
  if {[string match */rtl/core/neorv32_cpu_alu_cfu.vhd $f]} { set f $cfu }
  lappend fl $f
}
close $fp
lappend fl $root/rtl/irq_lat_mon.vhd
add_files -norecurse $fl
set_property library neorv32 [get_files $fl]
set_property file_type {VHDL 2008} [get_files $fl]
puts "CFU_SOURCE: [get_files -quiet *neorv32_cpu_alu_cfu.vhd]"
puts "IMEM_IMAGE: [get_files -quiet *imem_image*]"
# block-design wrappers (plain VHDL, library xil_defaultlib)
set wr [list $root/rtl/bd/irq_bd_pkg.vhd $root/rtl/bd/irq_bd_sync.vhd $root/rtl/bd/int8irq_bd_cpu.vhd \
             $root/rtl/bd/irq_bd_bus_switch.vhd $root/rtl/bd/irq_bd_monitor.vhd]
add_files -norecurse $wr
add_files -fileset constrs_1 -norecurse $root/constraints/int8_irq_bd_zcu104.xdc
update_compile_order -fileset sources_1

proc ipdef {name} { return [lindex [lsort [get_ipdefs -filter "NAME == $name"]] end] }

create_bd_design int8_irq_bd

# ---------------- clock and reset (one hierarchy box) ----------------
create_bd_cell -type hier clock_and_reset
create_bd_pin -dir O -type clk clock_and_reset/clock_100mhz
create_bd_pin -dir O -type rst clock_and_reset/reset_done_n
create_bd_cell -type ip -vlnv [ipdef zynq_ultra_ps_e] clock_and_reset/zynq_ps_makes_the_clock
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells clock_and_reset/zynq_ps_makes_the_clock]
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] [get_bd_cells clock_and_reset/zynq_ps_makes_the_clock]
create_bd_cell -type ip -vlnv [ipdef proc_sys_reset] clock_and_reset/reset_helper
connect_bd_net [get_bd_pins clock_and_reset/zynq_ps_makes_the_clock/pl_clk0] \
    [get_bd_pins clock_and_reset/reset_helper/slowest_sync_clk] [get_bd_pins clock_and_reset/clock_100mhz]
connect_bd_net [get_bd_pins clock_and_reset/zynq_ps_makes_the_clock/pl_resetn0] [get_bd_pins clock_and_reset/reset_helper/ext_reset_in]
connect_bd_net [get_bd_pins clock_and_reset/reset_helper/peripheral_aresetn] [get_bd_pins clock_and_reset/reset_done_n]

# ---------------- the system ----------------
create_bd_cell -type module -reference irq_bd_sync       doorbell_sync
create_bd_cell -type module -reference int8irq_bd_cpu    riscv_brain_with_int8_math_helper
create_bd_cell -type module -reference irq_bd_bus_switch address_switch
create_bd_cell -type module -reference irq_bd_monitor    stopwatch_latency_monitor
# every address that is not the monitor: no device in this design, answer "bus error"
# (inline HDL constant, the current replacement for the discontinued xlconstant IP)
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 nothing_else_on_bus
set_property -dict [list CONFIG.CONST_WIDTH {34} CONFIG.CONST_VAL {1}] [get_bd_cells nothing_else_on_bus]
# talking light: the UART send line is high when quiet, so NOT(line) flickers while text goes out
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 talking_light_not_gate
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] [get_bd_cells talking_light_not_gate]

create_bd_port -dir I doorbell_button
create_bd_port -dir O doorbell_led
create_bd_port -dir O too_slow_led
create_bd_port -dir O awake_led
create_bd_port -dir O talking_led
create_bd_port -dir O uart_text_out
create_bd_port -dir I uart_text_in

proc p {x} { return [get_bd_pins $x] }
set brain riscv_brain_with_int8_math_helper
connect_bd_net [p clock_and_reset/clock_100mhz] \
    [p doorbell_sync/clk] [p $brain/clk] [p address_switch/clk] [p stopwatch_latency_monitor/clk]
connect_bd_net [p clock_and_reset/reset_done_n] \
    [p $brain/resetn] [p address_switch/resetn] [p stopwatch_latency_monitor/resetn] [get_bd_ports awake_led]

connect_bd_net [get_bd_ports doorbell_button] [p doorbell_sync/button]
connect_bd_net [p doorbell_sync/doorbell] [p $brain/irq_doorbell] \
    [p stopwatch_latency_monitor/doorbell] [get_bd_ports doorbell_led]
connect_bd_net [p $brain/trace_valid] [p stopwatch_latency_monitor/trace_valid]
connect_bd_net [p $brain/trace_intr]  [p stopwatch_latency_monitor/trace_intr]
connect_bd_net [p $brain/bus_request] [p address_switch/cpu_request]
connect_bd_net [p address_switch/cpu_reply] [p $brain/bus_reply]
connect_bd_net [p address_switch/monitor_request] [p stopwatch_latency_monitor/bus_request]
connect_bd_net [p stopwatch_latency_monitor/bus_reply] [p address_switch/monitor_reply]
connect_bd_net [p nothing_else_on_bus/dout] [p address_switch/other_reply]
connect_bd_net [p stopwatch_latency_monitor/too_slow] [get_bd_ports too_slow_led]
connect_bd_net [p $brain/uart_txd] [get_bd_ports uart_text_out] [p talking_light_not_gate/Op1]
connect_bd_net [p talking_light_not_gate/Res] [get_bd_ports talking_led]
connect_bd_net [get_bd_ports uart_text_in] [p $brain/uart_rxd]

assign_bd_address
regenerate_bd_layout -hierarchy [get_bd_cells clock_and_reset]
regenerate_bd_layout
if {[file exists $root/scripts/int8_irq_bd_layout.native]} {
  regenerate_bd_layout -layout_file $root/scripts/int8_irq_bd_layout.native
  puts "LAYOUT_FILE_USED: $root/scripts/int8_irq_bd_layout.native"
}
set vrc [catch {validate_bd_design} vmsg]
puts "VALIDATE_RC: $vrc $vmsg"
if {$vrc} { error "validate_bd_design failed: $vmsg" }
save_bd_design
puts "BD_VALIDATED"
set segs [get_bd_addr_segs -quiet]
puts "ADDR_SEGMENTS: [llength $segs] ($segs)"
foreach c [lsort [get_bd_cells -hierarchical]] { puts "BD_CELL: $c [get_property VLNV $c]" }
write_bd_tcl -force $root/build/int8_irq_bd_export.tcl

make_wrapper -files [get_files int8_irq_bd.bd] -top -import
set_property top int8_irq_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1
if {[info exists ::env(BD_SYNTH)] && $::env(BD_SYNTH) eq "0"} { puts "STOP_AFTER_BD"; return }

generate_target all [get_files int8_irq_bd.bd]
puts "GENERATE_TARGET_DONE"

launch_runs synth_1 -jobs 2
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synthesis failed" }
open_run synth_1
report_utilization -file $rpt/post_synth_utilization.rpt
report_utilization -hierarchical -file $rpt/post_synth_utilization_hier.rpt
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"
open_run impl_1
report_timing_summary -max_paths 10 -file $rpt/post_route_timing_summary.rpt
report_utilization -file $rpt/post_route_utilization.rpt
report_utilization -hierarchical -file $rpt/post_route_utilization_hier.rpt
report_drc -file $rpt/post_route_drc.rpt
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
puts "WHS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]"
puts "BITSTREAM: [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit]"
puts "BUILD_BD_DONE"
