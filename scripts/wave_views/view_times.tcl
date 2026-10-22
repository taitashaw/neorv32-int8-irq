# Times for scripts/waves_view.tcl, all in ns of simulated time, from the verified runs:
#   vt(view) = {k m lat bound zoom_start zoom_end log_start run_end}
# Final design (21 Oct): GETACC CFU, the handler uses the CFU and saves/restores the
# accumulator (image sim/images/dot4_getacc, run sim/run_dot4_getacc, gate PASS).
# The earlier times (handler without the CFU, image dot4_final) are kept in
# archive_pre_getacc_21oct/scripts/wave_views/view_times.tcl.
# dot4ins: first DOT4ACC of test vector 1 (reference pass, interrupts off); k = clock edge
#          where start_i rises (the CPU starts the CFU), m = edge where valid_o rises
#          (scripts/find_cfu_ops.py on sim/gui_findtimes_dot4/find_dot4_times.vcd: start sampled
#          at 640,655 ns, valid sampled at 640,675 ns). The code before and in the reference
#          pass is the same in the dot4_getacc image (sim/logs/dot4_getacc_disasm.txt differs
#          from dot4_final only in the handler and in "li a2,1" at 0x59e, same size); the view's
#          check file confirms the values at the markers.
# irqdot4: worst DOT4 sample of sim/run_dot4_getacc (74 cycles, fired at 0x412, CSV time
#          27,354,705 ns): m = CSV time - 10 ns (the sample is written one edge after the
#          response), k = m - 10 x 74.
# irqcfu:  worst DOT4 sample that fired inside a DOT4ACC (50 cycles, fired at 0x3ee,
#          CSV time 32,475,255 ns, sim/run_dot4_getacc/irq_pc.csv; 2,674 of 19,175 samples
#          fired inside a DOT4ACC).
# getacc:  the irqcfu interrupt followed through the handler; gt(getacc) = clock edges where
#          the CPU starts GETACC, SETACC x0 (the handler's own use), SETACC t0 (restore), and
#          the first instruction back in the interrupted code, from scripts/find_getacc_times.tcl
#          (sim/logs/find_getacc_times.log).
# fail:    first CRIT sample above the bound in sim/run_fail_crit100 (905 cycles, CSV time
#          19,190,675 ns; the rerun's CSV is byte-identical to the earlier one).
set vt(dot4ins) {640645 640665 0 0 640615 640705 640000 640800}
set vt(irqdot4) {27353955 27354695 74 133 27353875 27354860 27353760 27354980}
set vt(irqcfu)  {32474745 32475245 50 133 32474665 32475365 32474550 32475530}
set vt(fail)    {19181615 19190665 905 521 19181215 19191065 19181000 19191300}
# getacc (sim/logs/find_getacc_times.log): DOT4ACC at 0x3ee starts at 32,474,915 (acc -21 before it, 6 after it),
# handler first instruction 0x7c0, GETACC starts at 32,475,345 (answer 6, stored to the stack at
# 0x80001f38), the handler's SETACC x0 starts at 32,475,615 (acc 6 -> 0), SETACC t0 starts at
# 32,475,855 (rs1 6, acc 0 -> 6), mret at 0x814, first instruction back at 0x3f2 on edge
# 32,476,315 with acc 6; the next DOT4ACC starts from 6.
# 22 Oct: getacc zoom 32,475,200 to 32,476,485 (handler entry to just past F, markers C to F only)
# and irqdot4 zoom end 27,354,860, so every marker label fits beside its line without covering
# another one (the irqdot4 B label had been pushed left across the cursor).
set vt(getacc)  {32474745 32475245 50 133 32475200 32476485 32474550 32476515}
set gt(getacc)  {32475345 32475615 32475855 32476315}
