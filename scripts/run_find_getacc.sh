#!/usr/bin/env bash
# Runs the two batch helpers on the view snapshots (21 Oct): getacc marker times, and the
# instruction-cache refills inside the worst DOT4 interrupt (irqdot4).
B=$(cd "$(dirname "$0")/.." \&\& pwd)
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
cd $B/sim/gui_getacc && FIND_T0=32474650 FIND_T1=32477245 xsim tb_snap -tclbatch $B/scripts/find_getacc_times.tcl -log find_getacc.xsim.log > $B/sim/logs/find_getacc_times.log 2>&1
cd $B/sim/gui_irqdot4 && CNT_K=27353955 CNT_M=27354695 xsim tb_snap -tclbatch $B/scripts/count_ic_refills.tcl -log count_ic.xsim.log > $B/sim/logs/count_ic_irqdot4.log 2>&1
cd $B/sim/gui_irqcfu && CNT_K=32474745 CNT_M=32475245 xsim tb_snap -tclbatch $B/scripts/count_ic_refills.tcl -log count_ic.xsim.log > $B/sim/logs/count_ic_irqcfu.log 2>&1
echo "FIND_ALL_DONE $(date)"
