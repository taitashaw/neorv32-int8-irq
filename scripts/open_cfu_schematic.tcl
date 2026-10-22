# Opens the elaborated RTL schematic of the INT8 helper (rtl/neorv32_cpu_alu_cfu.vhd, 2-stage
# CFU) alone, in its own Vivado window (run by scripts/open_schematic.sh). Copied from the
# INT8 project; the CFU source is the same file, copied unchanged into rtl/. Elaboration only
# (synth_design -rtl): the schematic shows the four 8x8 multipliers, the adder tree, the
# accumulator adder and the registers as the tool reads them from the VHDL.
# Environment (test mode only): VIEW_SHOT=<png> takes a screenshot, VIEW_AUTOQUIT=1 then quits
set root [file normalize [file dirname [info script]]/..]
set rc [catch {
    read_vhdl -vhdl2008 -library neorv32 $root/neorv32/rtl/core/neorv32_package.vhd
    read_vhdl -vhdl2008 -library neorv32 $root/rtl/neorv32_cpu_alu_cfu.vhd
    synth_design -rtl -top neorv32_cpu_alu_cfu -part xczu7ev-ffvc1156-2-e -name int8_helper_rtl
    set cells [get_cells -hierarchical]
    puts "CFU_RTL_CELLS: [llength $cells]"
    foreach c [lsort $cells] { puts "CFU_RTL_CELL: $c [get_property REF_NAME $c]" }
} err]
if {$rc} { puts "OPEN_SCHEMATIC_ERROR: $err" } else { puts "OPEN_SCHEMATIC_ELABORATED" }

proc show_it {} {
    if {[catch {show_schematic -name int8_helper_schematic [concat [get_cells] [get_ports]]} e]} {
        puts "OPEN_SCHEMATIC_ERROR: $e"
    } else {
        puts "OPEN_SCHEMATIC_OK"
    }
    if {[info exists ::env(VIEW_SHOT)]} {
        after 10000 {
            catch {exec import -window root -display $::env(DISPLAY) $::env(VIEW_SHOT)} e
            puts "VIEW_SHOT: $::env(VIEW_SHOT) $e"
            if {[info exists ::env(VIEW_AUTOQUIT)]} { after 1000 exit }
        }
    } elseif {[info exists ::env(VIEW_AUTOQUIT)]} { after 5000 exit }
}
if {!$rc} { after 6000 show_it } elseif {[info exists ::env(VIEW_AUTOQUIT)]} { exit }
