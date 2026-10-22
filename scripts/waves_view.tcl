# XSim waveform views of the combined design (NEORV32 + INT8 CFU + latency monitor),
# on the real simulation of the README. Sourced by scripts/open_waves.sh as
#   xsim tb_snap -gui -tclbatch scripts/waves_view.tcl
# Adapted from the two source projects' scripts/waves_view.tcl (the profiler's run,
# log and marker logic; the INT8 project's story groups).
#
# Views (env VIEW):
#   dot4ins  one DOT4ACC instruction (snapshot sim/gui_dot4, DOT4 final image): the first
#            DOT4ACC of test vector 1 in the reference pass (interrupts off). Same numbers
#            as the INT8 project's view: weights 10 -12 38 98, inputs -50 6 -17 -53.
#   irqdot4  the worst-case interrupt of the DOT4 scenario (snapshot sim/gui_dot4): the
#            CPU is running the INT8 inference on the CFU when the interrupt arrives.
#   irqcfu   the worst interrupt that fired inside a DOT4ACC instruction (snapshot sim/gui_irqcfu).
#   getacc   the same interrupt as irqcfu, followed through the whole handler: GETACC copies
#            the running total, the handler's own SETACC x0 clears it, SETACC t0 puts the copy
#            back, and the inference continues (snapshot sim/gui_getacc, final image
#            sim/images/dot4_getacc). Markers C to F come from scripts/find_getacc_times.tcl.
#   fail     the deliberate gate failure (snapshot sim/gui_fail_crit100, CRIT_N = 100):
#            first CRIT sample above the bound of 521.
# The times below come from the verified runs (see the README and
# scripts/wave_views/*_check.txt, which this script writes while it runs).
#
# The run stops just after the event, long before the testbench's std.env.finish, so
# XSim keeps the wave window in front. Only the signals of the view are logged,
# starting a little before the zoom window.
# The view itself (groups, names, radixes, colours, markers, zoom) lives in
# scripts/wave_views/<view>.wcfg. With VIEW_BUILD=1 this script rebuilds that file from
# the add_wave commands below, then opens it. Otherwise it opens the saved file.
# VIEW_SHOT=<png>   take a screenshot of the X display after the view is open
# VIEW_AUTOQUIT=1   quit after that (only for tests; scripts/open_view.sh does not set it)

set here [file normalize [file dirname [info script]]]
set view irqdot4
if {[info exists ::env(VIEW)]} { set view $::env(VIEW) }

set W  /int8irq_wave_top
set T  $W/tb
set D  $T/dut
set CC "$D/neorv32_inst/\\core_complex_gen(0)\\/core_complex_inst"
set C  "$CC/cpu_inst/cpu_control_inst"
set F  "$CC/cpu_inst/cpu_alu_inst/cpu_alu_cfu_enabled/cpu_alu_cfu_inst"
set H  $W/helper
set M  $D/mon_enabled/mon_inst

source $here/wave_views/view_times.tcl
if {![info exists vt($view)]} { puts "VIEW must be one of: [array names vt]"; quit }
# k = first marker time, m = second marker time (ns), lat = logged latency (cycles, 0 for dot4ins)
lassign $vt($view) k m lat bound z0 z1 tlog tend

# Group colours avoid the colours XSim uses for value states (~/.Xilinx/Vivado/2025.2/waveform/wv.ini):
# red = X (unknown), orange = U (uninitialised), blue = Z (high impedance), grey = don't care,
# yellow = cursor, white = selected. A red, orange, blue or grey row in these views is therefore
# always an X, U, Z or don't-care value, never a group colour.
# Row names are the RTL names (signal path inside the instance shown before the dot:
# ctrl = cpu_control_inst, cfu = cpu_alu_cfu_inst, mon = the latency monitor, trace = the
# CPU trace port, helper = the simulation-only viewing helper tb/int8irq_wave_helper.vhd).
# Testbench signals (clk, rstn, irq_mei, p_ic_*, smp_*, viol) keep their testbench names.
set irq_groups [list \
  [list "0 clock and reset" #00FF00 [list \
     [list "clk" "" $T/clk] \
     [list "rstn" "" $T/rstn]]] \
  [list "1 interrupt request" #FF55FF [list \
     [list "irq_mei" "" $T/irq_mei] \
     [list "ctrl.irq_pnd\[2\]" "" "$C/irq_pnd\[2\]"] \
     [list "ctrl.irq_buf\[2\]" "" "$C/irq_buf\[2\]"]]] \
  [list "2 execute" #00FFFF [list \
     [list "ctrl.exec.state" "" $C/exec.state] \
     [list "ctrl.exec.pc" hex $C/exec.pc] \
     [list "ctrl.exec.ir" hex $C/exec.ir] \
     [list "cfu.start_i" "" "$F/start_i"] \
     [list "cfu.valid_o" "" "$F/valid_o"] \
     [list "trace.valid" "" $D/trace.valid] \
     [list "trace.pc_rdata" hex $D/trace.pc_rdata]]] \
  [list "3 trap entry" #B58CFF [list \
     [list "ctrl.irq_fire\[0\]" "" "$C/irq_fire\[0\]"] \
     [list "ctrl.env_enter" "" $C/env_enter] \
     [list "p_ic_stb" "" $T/p_ic_stb] \
     [list "p_ic_ack" "" $T/p_ic_ack] \
     [list "trace.intr" "" $D/trace.intr]]] \
  [list "4 latency monitor" #20C0A0 [list \
     [list "mon.pend" "" $M/pend] \
     [list "mon.cnt" unsigned $M/cnt] \
     [list "smp_valid" "" $T/smp_valid] \
     [list "smp_lat" unsigned $T/smp_lat] \
     [list "mon.st_min" unsigned $M/st_min] \
     [list "mon.st_max" unsigned $M/st_max] \
     [list "mon.st_count" unsigned $M/st_count]]] \
  [list "5 gate" #FFA0D0 [list \
     [list "mon.bound" unsigned $M/bound] \
     [list "viol" "" $T/viol] \
     [list "mon.st_nviol" unsigned $M/st_nviol]]] \
]

set dot4_groups [list \
  [list "0 clock and reset" #00FF00 [list \
     [list "cfu.clk_i" "" "$F/clk_i"] \
     [list "cfu.rstn_i" "" "$F/rstn_i"]]] \
  [list "1 CFU inputs" #B58CFF [list \
     [list "cfu.start_i" "" "$F/start_i"] \
     [list "helper.instruction" "" $H/instruction] \
     [list "cfu.rs1_i" hex "$F/rs1_i"] \
     [list "cfu.rs2_i" hex "$F/rs2_i"] \
     [list "helper.a0" dec $H/a0] \
     [list "helper.a1" dec $H/a1] \
     [list "helper.a2" dec $H/a2] \
     [list "helper.a3" dec $H/a3] \
     [list "helper.b0" dec $H/b0] \
     [list "helper.b1" dec $H/b1] \
     [list "helper.b2" dec $H/b2] \
     [list "helper.b3" dec $H/b3]]] \
  [list "2 lane products" #20C0A0 [list \
     [list "helper.p0" dec $H/p0] \
     [list "helper.p1" dec $H/p1] \
     [list "helper.p2" dec $H/p2] \
     [list "helper.p3" dec $H/p3] \
     [list "cfu.dot4" dec "$F/dot4"]]] \
  [list "3 accumulator" #FFA0D0 [list \
     [list "cfu.acc" dec "$F/acc"]]] \
  [list "4 result" #FF55FF [list \
     [list "cfu.valid_o" "" "$F/valid_o"] \
     [list "cfu.result_o" dec "$F/result_o"] \
     [list "helper.ticks_since_go" dec $H/ticks_since_go]]] \
  [list "5 CPU" #00FFFF [list \
     [list "ctrl.exec.state" "" $C/exec.state] \
     [list "ctrl.exec.pc" hex $C/exec.pc] \
     [list "trace.valid" "" $D/trace.valid] \
     [list "trace.pc_rdata" hex $D/trace.pc_rdata] \
     [list "irq_mei" "" $T/irq_mei]]] \
]

set getacc_groups [list \
  [list "0 clock and reset" #00FF00 [list \
     [list "clk" "" $T/clk] \
     [list "rstn" "" $T/rstn]]] \
  [list "1 interrupt and latency" #FF55FF [list \
     [list "irq_mei" "" $T/irq_mei] \
     [list "trace.intr" "" $D/trace.intr] \
     [list "smp_lat" unsigned $T/smp_lat]]] \
  [list "2 execute" #00FFFF [list \
     [list "ctrl.exec.pc" hex $C/exec.pc] \
     [list "trace.valid" "" $D/trace.valid] \
     [list "trace.pc_rdata" hex $D/trace.pc_rdata]]] \
  [list "3 CFU" #B58CFF [list \
     [list "cfu.start_i" "" "$F/start_i"] \
     [list "helper.instruction" "" $H/instruction] \
     [list "cfu.rs1_i" hex "$F/rs1_i"] \
     [list "cfu.valid_o" "" "$F/valid_o"] \
     [list "cfu.result_o" dec "$F/result_o"]]] \
  [list "4 accumulator and stack copy" #FFA0D0 [list \
     [list "cfu.acc" dec "$F/acc"] \
     [list "trace.mem_wdata" hex $D/trace.mem_wdata] \
     [list "trace.mem_rdata" hex $D/trace.mem_rdata]]] \
]

if {$view eq "dot4ins"} { set groups $dot4_groups } elseif {$view eq "getacc"} { set groups $getacc_groups } else { set groups $irq_groups }
# getacc: extra marker times (clock edges, ns): GETACC starts, SETACC x0 starts, SETACC t0 starts,
# first instruction back in the interrupted code
if {$view eq "getacc"} { lassign $gt(getacc) tg tc tr tb }
set wcfg $here/wave_views/int8irq_$view.wcfg

file mkdir $here/wave_views
set chk [open $here/wave_views/int8irq_${view}_check.txt w]
proc chk {args} { global chk; puts $chk [join $args]; flush $chk; puts "VIEWCHECK: [join $args]" }
proc val {p} {
  if {[string first "\\" $p] >= 0} {
    set i [string last / $p]
    current_scope [string range $p 0 [expr {$i-1}]]
    set n [string range $p [expr {$i+1}] end]
    if {[catch {set v [get_value -radix unsigned $n]}]} { if {[catch {set v [get_value $n]}]} { set v ? } }
    current_scope /
    return $v
  }
  if {[catch {set v [get_value -radix unsigned $p]}]} { if {[catch {set v [get_value $p]}]} { set v ? } }
  return $v
}

# 1. run up to just before the window without logging (fast)
run ${tlog}ns
# log_wave skips record fields and single bits, so log the whole signal they belong to
foreach g $groups { foreach s [lindex $g 2] {
  set lp [regsub {\[[0-9]+\]$} [lindex $s 2] {}]
  set lp [regsub {\.[a-z_0-9]+$} $lp {}]
  if {[string first "\\" $lp] >= 0} {
    set i [string last / $lp]
    current_scope [string range $lp 0 [expr {$i-1}]]
    if {[catch {log_wave [string range $lp [expr {$i+1}] end]} e]} { puts "LOG_WARN: $lp $e" }
    current_scope /
  } elseif {[catch {log_wave $lp} e]} { puts "LOG_WARN: $lp $e" }
} }

# 2. run through the event, sampling values to prove the markers are right
if {$view eq "dot4ins"} {
  run [expr {$k - 5 - $tlog}]ns
  chk "t=[expr {$k-5}]ns  (just before the edge at $k ns) start_i=[val $F/start_i]"
  run 10ns
  chk "t=[expr {$k+5}]ns  (just after the edge at $k ns)  start_i=[val $F/start_i] rs1=[val $F/rs1_i] rs2=[val $F/rs2_i] acc=[val $F/acc] instruction=[val $H/instruction]"
  run [expr {$m - 5 - ($k + 5)}]ns
  chk "t=[expr {$m-5}]ns  (just before the edge at $m ns) valid_o=[val $F/valid_o]"
  run 10ns
  chk "t=[expr {$m+5}]ns  (just after the edge at $m ns)  valid_o=[val $F/valid_o] result=[val $F/result_o] acc=[val $F/acc] dot4_products=[val $H/p0],[val $H/p1],[val $H/p2],[val $H/p3]"
  run [expr {$tend - ($m + 5)}]ns
  chk "t=${tend}ns run stopped here; marker A start_i = $k ns, marker B valid_o = $m ns, gap [expr {$m-$k}] ns = [expr {($m-$k)/10}] ticks"
} else {
  run [expr {$k - 15 - $tlog}]ns
  chk "t=[expr {$k-15}]ns (between edge k-2 and k-1) irq_mei=[val $T/irq_mei]"
  run 10ns
  chk "t=[expr {$k-5}]ns  (between edge k-1 and k)   irq_mei=[val $T/irq_mei] monitor_pend=[val $M/pend]"
  run 10ns
  chk "t=[expr {$k+5}]ns  (just after edge k)        monitor_pend=[val $M/pend]"
  run [expr {$m - 15 - ($k + 5)}]ns
  chk "t=[expr {$m-15}]ns (between edge m-2 and m-1) trace.valid=[val $D/trace.valid] trace.intr=[val $D/trace.intr]"
  run 10ns
  chk "t=[expr {$m-5}]ns  (between edge m-1 and m)   trace.valid=[val $D/trace.valid] trace.intr=[val $D/trace.intr] stopwatch=[val $M/cnt]"
  run 10ns
  chk "t=[expr {$m+5}]ns  (just after edge m)        smp_valid=[val $T/smp_valid] smp_lat=[val $T/smp_lat] st_last=[val $M/st_last] st_max=[val $M/st_max] viol=[val $T/viol] nviol=[val $M/st_nviol] bound=[val $M/bound]"
  set cur [expr {$m + 5}]
  if {$view eq "getacc"} {
    foreach {t what} [list $tg "C GETACC" $tc "D SETACC x0" $tr "E SETACC t0"] {
      run [expr {$t + 5 - $cur}]ns
      chk "t=[expr {$t+5}]ns  (just after edge $t, $what) start_i=[val $F/start_i] instruction=[val $H/instruction] rs1=[val $F/rs1_i] acc=[val $F/acc]"
      run 20ns
      chk "t=[expr {$t+25}]ns (2 ticks later)             valid_o=[val $F/valid_o] result=[val $F/result_o] acc=[val $F/acc]"
      set cur [expr {$t + 25}]
    }
    run [expr {$tb + 5 - $cur}]ns
    chk "t=[expr {$tb+5}]ns  (just after edge $tb, F back) trace.valid=[val $D/trace.valid] trace.pc=[val $D/trace.pc_rdata] trace.intr=[val $D/trace.intr] acc=[val $F/acc]"
    set cur [expr {$tb + 5}]
  }
  run [expr {$tend - $cur}]ns
  if {$view eq "getacc"} {
    chk "t=${tend}ns run stopped here; edge k = ${k} ns and edge m = ${m} ns (markers A and B of the irqcfu view), m - k = [expr {$m-$k}] ns = $lat cycles of 10 ns"
  } else {
    chk "t=${tend}ns run stopped here; marker A = edge k = ${k} ns, marker B = edge m = ${m} ns, B - A = [expr {$m-$k}] ns = $lat cycles of 10 ns"
  }
}
close $chk

proc add_one {opts path} {
  # add_wave does not find objects under the escaped generate scope
  # "\core_complex_gen(0)\" by full path, but it does relative to that scope
  if {[string first "\\" $path] >= 0} {
    set i [string last / $path]
    set ok [expr {![catch {current_scope [string range $path 0 [expr {$i-1}]]; add_wave {*}$opts [string range $path [expr {$i+1}] end]} e0]}]
    current_scope /
    if {$ok} { return }
  }
  if {[catch {add_wave {*}$opts $path} e1]} {
    if {[catch {add_wave {*}$opts [get_objects $path]} e2]} {
      set whole [regsub {\[[0-9]+\]$} $path {}]
      if {[catch {add_wave {*}$opts -radix bin $whole} e3]} {
        puts "VIEW_WARN: could not add $path ($e1)"
      } else { puts "VIEW_NOTE: $path shown as the whole vector $whole" }
    }
  }
}

# Marker labels are short on purpose: XSim appends ": <time>" to each label, and close markers
# would otherwise cover each other. getacc shows C to F only: A and B of the same interrupt are
# in the irqcfu view, and B is only 100 ns before C, so its label would cover C's.
# Marker label colour is XSim's MARKER_COLOR (~/.Xilinx/Vivado/2025.2/waveform/wv.ini), set to
# 160 210 255 on 22 Oct: black label text on it is 13.2:1 (on the default 0 128 255 it was 5.5:1).
proc build_view {} {
  global groups wcfg k m lat bound z0 z1 view
  foreach g $groups {
    lassign $g gname gcolor sigs
    set gh [add_wave_group $gname]
    foreach s $sigs {
      lassign $s name radix path
      set opts [list -into $gh -color $gcolor -name $name]
      if {$radix ne ""} { lappend opts -radix $radix }
      add_one $opts $path
    }
  }
  if {$view eq "dot4ins"} {
    add_wave_marker -name "A start_i" $k ns
    add_wave_marker -name "B valid_o" $m ns
  } elseif {$view eq "getacc"} {
    global tg tc tr tb
    add_wave_marker -name "C GETACC" $tg ns
    add_wave_marker -name "D SETACC 0" $tc ns
    add_wave_marker -name "E SETACC t0" $tr ns
    add_wave_marker -name "F back" $tb ns
  } else {
    add_wave_marker -name "A irq" $k ns
    add_wave_marker -name "B entry +$lat" $m ns
    # the limit marker only where it does not cover marker B
    if {abs($bound - $lat) > 30} { add_wave_marker -name "C bound +$bound" [expr {$k + 10 * $bound}] ns }
  }
  save_wave_config $wcfg
  close_wave_config -force [current_wave_config]
  # zoom and cursor have no Tcl command: write them into the saved file
  set f [open $wcfg r]; set x [read $f]; close $f
  set zs "<zoom_setting>\n      <ZoomStartTime time=\"[expr {$z0*1000}] ps\"></ZoomStartTime>\n      <ZoomEndTime time=\"[expr {$z1*1000}] ps\"></ZoomEndTime>\n      <Cursor1Time time=\"[expr {$m*1000}] ps\"></Cursor1Time>\n   </zoom_setting>"
  if {![regsub {<zoom_setting>.*?</zoom_setting>} $x $zs x]} {
    regsub {</db_ref_list>} $x "</db_ref_list>\n   $zs" x
  }
  # wider name column so the plain-English names fit
  if {![regsub {<NameColumnWidth column_width="[0-9]+">} $x {<NameColumnWidth column_width="330">} x]} {
    regsub {</zoom_setting>} $x "</zoom_setting>\n   <column_width_setting>\n      <NameColumnWidth column_width=\"330\"></NameColumnWidth>\n      <ValueColumnWidth column_width=\"130\"></ValueColumnWidth>\n   </column_width_setting>" x
  }
  regsub {<ValueColumnWidth column_width="[0-9]+">} $x {<ValueColumnWidth column_width="130">} x
  # open every group
  regsub -all {(<wvobject type="group" fp_name="[^"]+">\s*<obj_property name="label">[^<]*</obj_property>\s*<obj_property name="DisplayName">label</obj_property>)} $x "\\1\n      <obj_property name=\"isExpanded\"></obj_property>" x
  set f [open $wcfg w]; puts -nonewline $f $x; close $f
  puts "WCFG_BUILT: $wcfg"
}

proc show_view {} {
  global wcfg
  if {[info exists ::env(VIEW_BUILD)] || ![file exists $wcfg]} {
    if {[catch build_view e]} { puts "VIEW_ERROR: build failed: $e" }
  }
  if {[catch {open_wave_config $wcfg} e]} { puts "VIEW_ERROR: open failed: $e" }
  puts "WAVES_VIEW_OK: $wcfg"
  if {[info exists ::env(VIEW_SHOT)]} {
    after 8000 {
      catch {exec import -window root -display $::env(DISPLAY) $::env(VIEW_SHOT)} e
      puts "VIEW_SHOT: $::env(VIEW_SHOT) $e"
      if {[info exists ::env(VIEW_AUTOQUIT)]} { after 1000 quit }
    }
  } elseif {[info exists ::env(VIEW_AUTOQUIT)]} { after 3000 quit }
}

# open the view only after the window has its full size, so the saved zoom holds
after 6000 show_view
