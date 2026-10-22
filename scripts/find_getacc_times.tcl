# Batch helper (no GUI): finds the clock edges of the CFU operations and the return from the
# handler around one interrupt, for the "getacc" wave view. Run in a gui snapshot folder:
#   FIND_T0=<ns, 5 ns after a clock edge> FIND_T1=<ns> xsim tb_snap -tclbatch scripts/find_getacc_times.tcl
# Prints one FOUND line per event: the clock edge (sample time - 5 ns) and the values just after it.
set W  /int8irq_wave_top
set T  $W/tb
set D  $T/dut
set CC "$D/neorv32_inst/\\core_complex_gen(0)\\/core_complex_inst"
set F  "$CC/cpu_inst/cpu_alu_inst/cpu_alu_cfu_enabled/cpu_alu_cfu_inst"
set H  $W/helper
proc val {p} {
  if {[string first "\\" $p] >= 0} {
    set i [string last / $p]
    current_scope [string range $p 0 [expr {$i-1}]]
    set n [string range $p [expr {$i+1}] end]
    if {[catch {set v [get_value -radix dec $n]}]} { if {[catch {set v [get_value $n]}]} { set v ? } }
    current_scope /
    return $v
  }
  if {[catch {set v [get_value -radix dec $p]}]} { if {[catch {set v [get_value $p]}]} { set v ? } }
  return $v
}
proc hexv {p} {
  if {[catch {set v [get_value -radix hex $p]}]} { set v ? }
  return $v
}
set t0 $::env(FIND_T0); set t1 $::env(FIND_T1)
run ${t0}ns
set t $t0
set in_handler 0; set seen_mret 0
while {$t < $t1} {
  set ins [val $H/instruction]
  if {$ins ne "none"} {
    puts "FOUND cfu edge=[expr {$t-5}] instruction=$ins rs1=[val $F/rs1_i] acc=[val $F/acc] result=[val $F/result_o]"
  }
  if {[val $D/trace.valid] eq "1"} {
    set pc [hexv $D/trace.pc_rdata]
    if {[val $D/trace.intr] eq "1"} { set in_handler 1; puts "FOUND handler_first edge=[expr {$t-5}] pc=$pc" }
    if {$in_handler && $seen_mret} { puts "FOUND back edge=[expr {$t-5}] pc=$pc acc=[val $F/acc]"; set in_handler 0; set seen_mret 0 }
    set cmd [string tolower [hexv $D/trace.cmd32]]
    if {$in_handler && $cmd eq "00512423"} { puts "FOUND save_store edge=[expr {$t-5}] pc=$pc addr=[hexv $D/trace.mem_addr] wdata=[hexv $D/trace.mem_wdata]" }
    if {$in_handler && $cmd eq "00812283"} { puts "FOUND restore_load edge=[expr {$t-5}] pc=$pc addr=[hexv $D/trace.mem_addr] rdata=[hexv $D/trace.mem_rdata]" }
    if {$in_handler && $cmd eq "30200073"} { set seen_mret 1; puts "FOUND mret edge=[expr {$t-5}] pc=$pc" }
  }
  run 10ns
  incr t 10
}
puts "FIND_DONE t=$t"
quit
