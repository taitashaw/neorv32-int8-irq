# Batch helper (no GUI): counts instruction-cache refill requests (p_ic_stb) and acks (p_ic_ack)
# between two clock edges, to explain where an interrupt's cycles went.
#   CNT_K=<edge ns> CNT_M=<edge ns> xsim tb_snap -tclbatch scripts/count_ic_refills.tcl
set T /int8irq_wave_top/tb
set k $::env(CNT_K); set m $::env(CNT_M)
run [expr {$k + 5}]ns
set t [expr {$k + 5}]; set stb 0; set ack 0; set prev 0; set bursts 0
while {$t <= $m + 5} {
  set s [get_value $T/p_ic_stb]; set a [get_value $T/p_ic_ack]
  if {$s eq "1"} { incr stb; if {$prev eq "0"} { incr bursts } }
  if {$a eq "1"} { incr ack }
  set prev $s
  run 10ns; incr t 10
}
puts "ICCOUNT k=$k m=$m cycles=[expr {($m-$k)/10}] ic_stb_cycles=$stb ic_ack_cycles=$ack stb_runs=$bursts"
quit
