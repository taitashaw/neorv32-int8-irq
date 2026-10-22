#!/usr/bin/env bash
# Test of every picture on private Xvfb displays :83 to :89 (one window per display, so no window
# covers another; the user's own display is never used). Rebuilds the wave view files (VIEW_BUILD=1),
# takes one screenshot per window into docs/gui_test_screenshots/ and quits each window.
B=$(cd "$(dirname "$0")/.." \&\& pwd)
T=$B/build/gui_test; S=$B/docs/gui_test_screenshots
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH LIBGL_ALWAYS_SOFTWARE=1
: > $T/xvfb.pids; : > $T/views.pids
d=83
for v in bd schematic dot4ins getacc irqcfu irqdot4 fail; do
  Xvfb :$d -screen 0 2600x1650x24 -nolisten tcp > $T/xvfb_$d.log 2>&1 &
  echo "$! :$d" >> $T/xvfb.pids
  d=$((d+1))
done
sleep 3
run_view() { # display view shot
  case "$2" in
    bd)        (cd $T && DISPLAY=$1 VIEW_SHOT=$3 VIEW_AUTOQUIT=1 vivado -mode gui -nojournal -log test_open_bd.log -source $B/scripts/open_bd.tcl > test_open_bd.out 2>&1) ;;
    schematic) (cd $T && DISPLAY=$1 VIEW_SHOT=$3 VIEW_AUTOQUIT=1 vivado -mode gui -nojournal -log test_open_schematic.log -source $B/scripts/open_cfu_schematic.tcl > test_open_schematic.out 2>&1) ;;
    *)         DISPLAY=$1 VIEW_BUILD=1 VIEW_SHOT=$3 VIEW_AUTOQUIT=1 $B/scripts/open_waves.sh $2 > $T/test_waves_$2.out 2>&1 ;;
  esac
}
run_view :83 bd        $S/vivado_bd.png & echo "$! bd" >> $T/views.pids
run_view :84 schematic $S/vivado_cfu_schematic.png & echo "$! schematic" >> $T/views.pids
run_view :85 dot4ins   $S/xsim_dot4ins_one_instruction.png & echo "$! dot4ins" >> $T/views.pids
run_view :86 getacc    $S/xsim_getacc_save_restore.png & echo "$! getacc" >> $T/views.pids
run_view :87 irqcfu    $S/xsim_irqcfu_worst_interrupt_in_dot4acc.png & echo "$! irqcfu" >> $T/views.pids
run_view :88 irqdot4   $S/xsim_irqdot4_worst_dot4_interrupt.png & echo "$! irqdot4" >> $T/views.pids
run_view :89 fail      $S/xsim_fail_gate_failure.png & echo "$! fail" >> $T/views.pids
wait $(awk '{print $1}' $T/views.pids)
while read -r p d; do kill "$p"; done < $T/xvfb.pids
echo "GUI_TEST_DONE $(date)"
