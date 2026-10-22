# Out-of-context synth + place + route of int8_irq_top (adapted from the profiler
# project's scripts/ooc_irqlat.tcl, which came from the stage 1 ooc_impl.tcl)
# usage: vivado -mode batch -source ooc_combined.tcl -tclargs <cfu_en> <mon_en> <freq_mhz> <outdir> <imem_image.vhd> <cfu_source.vhd>
set cfu  [lindex $argv 0]
set mon  [lindex $argv 1]
set fmhz [lindex $argv 2]
set out  [lindex $argv 3]
set img  [lindex $argv 4]
set cfusrc [lindex $argv 5]
set part xczu7ev-ffvc1156-2-e
set B [file normalize [file join [file dirname [info script]] ..]]
set R $B/neorv32
file mkdir $out
set fp [open $R/rtl/file_list_core.f r]
foreach l [split [read $fp] "\n"] {
  set l [string trim $l]
  if {$l eq ""} continue
  set f [string map [list {$NEORV32_HOME} $R] $l]
  if {[string match *neorv32_imem_image.vhd $f]} { set f $img }
  if {[string match */rtl/core/neorv32_cpu_alu_cfu.vhd $f]} { set f $cfusrc }
  read_vhdl -vhdl2008 -library neorv32 $f
}
close $fp
read_vhdl -vhdl2008 -library neorv32 $B/rtl/irq_lat_mon.vhd
read_vhdl -vhdl2008 -library neorv32 $B/rtl/int8_irq_top.vhd
set hz [expr {int($fmhz * 1000000)}]
synth_design -top int8_irq_top -part $part -mode out_of_context -generic CLOCK_FREQUENCY=$hz -generic CFU_EN=$cfu -generic MON_EN=$mon -generic SMP_PORT_EN=false -generic ICACHE_EN=true
set per [format %.3f [expr {1000.0 / $fmhz}]]
create_clock -name clk -period $per [get_ports clk_i]
report_utilization    -file $out/post_synth_utilization.rpt
report_timing_summary -file $out/post_synth_timing_summary.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization        -file $out/post_route_utilization.rpt
report_utilization -hierarchical -file $out/post_route_utilization_hier.rpt
report_timing_summary -max_paths 10 -file $out/post_route_timing_summary.rpt
report_timing -max_paths 5 -sort_by slack -file $out/post_route_worst_paths.rpt
report_drc                -file $out/post_route_drc.rpt
write_checkpoint -force $out/post_route.dcp
puts "DONE top=int8_irq_top cfu=$cfu cfusrc=$cfusrc mon=$mon f=$fmhz period=$per"
