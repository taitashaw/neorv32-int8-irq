#!/usr/bin/env python3
"""Write an XSim Tcl file that dumps short VCD windows around chosen samples.
Each window starts 300 ns before the request edge (time_ns - 10 * latency) and ends
100 ns after the sample. Samples are given as time_ns values from irq_samples.csv.
usage: make_vcd_windows.py <irq_samples.csv> <out.tcl> <vcd_name> <tb_name> <time_ns> [<time_ns> ...]"""
import csv, sys
csvp, out, vcd, tb = sys.argv[1:5]
want = sorted(int(t) for t in sys.argv[5:])
rows = {int(r['time_ns']): r for r in csv.DictReader(open(csvp))}
C = '{/%s/dut/neorv32_inst/\\core_complex_gen(0)\\/core_complex_inst/cpu_inst/cpu_control_inst}' % tb
L = [f"# VCD windows around the samples at {', '.join(map(str, want))} ns of {csvp}",
     f"set C {C}", f"open_vcd {vcd}",
     f"log_vcd /{tb}/clk /{tb}/irq_mei /{tb}/smp_valid /{tb}/smp_lat /{tb}/smp_drain /{tb}/smp_tag",
     f"log_vcd /{tb}/p_tr_valid /{tb}/p_tr_intr /{tb}/p_tr_pc /{tb}/p_exec /{tb}/p_dispatch /{tb}/p_trap /{tb}/p_pc_cur /{tb}/p_fe_valid /{tb}/p_ic_stb /{tb}/p_ic_ack /{tb}/p_cfu_start /{tb}/p_cfu_done",
     "log_vcd [get_objects $C/env_pend] [get_objects $C/env_enter] [get_objects $C/irq_buf] [get_objects $C/irq_pnd] [get_objects $C/irq_fire]",
     "stop_vcd"]
now = 0
for t in want:
    lat = int(rows[t]['latency'])
    s = t - 10 * lat - 300
    e = t + 100
    if s < now:
        s = now
    L.append(f"run {s - now}ns"); L.append("start_vcd"); L.append(f"run {e - s}ns"); L.append("stop_vcd")
    now = e
L.append("close_vcd")
open(out, 'w').write('\n'.join(L) + '\n')
print('\n'.join(L))
