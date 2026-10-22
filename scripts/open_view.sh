#!/usr/bin/env bash
# Opens the pictures of the combined design (final: GETACC CFU, handler saves the accumulator) on the current X display (default :0) and
# leaves them open (no auto-quit). Close each window with File > Exit.
#
# Usage: scripts/open_view.sh [view ...]
#   (no argument)  bd schematic irqdot4
#   bd             Vivado: the block design on the IP Integrator canvas
#   schematic      Vivado: the elaborated RTL schematic of the INT8 helper (the CFU) alone
#   dot4ins        XSim: one DOT4ACC instruction in the combined design
#   irqdot4        XSim: the worst-case DOT4 interrupt (74 cycles), groups 0 to 5
#   irqcfu         XSim: the worst interrupt that fired inside a DOT4ACC
#   getacc         XSim: that interrupt through the handler: GETACC saves the running total, SETACC restores it
#   fail           XSim: the deliberate gate failure (905 cycles, bound 521)
#   all            every one of the above (six windows; memory use not measured, open fewer if RAM is short)
# Example: scripts/open_view.sh bd dot4ins irqdot4
# Each window is its own process; their PIDs are written to build/gui_logs/open_view.pids.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export DISPLAY=${DISPLAY:-:0}
export LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-1}
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
unset VIEW_AUTOQUIT VIEW_SHOT VIEW_BUILD VIEW_EXPORT_LAYOUT
views="$*"; [ -z "$views" ] && views="bd schematic irqdot4"
[ "$views" = all ] && views="bd schematic dot4ins irqdot4 irqcfu getacc fail"
L=$ROOT/build/gui_logs; mkdir -p "$L"; : > "$L/open_view.pids"
if [ ! -f "$ROOT/build/vivado_bd/int8_irq_bd.xpr" ]; then
  case " $views " in *" bd "*) echo "block design project missing: run vivado -mode batch -source scripts/build_bd.tcl first"; exit 1;; esac
fi
for v in $views; do
  case "$v" in
    bd)        (cd "$L" && exec vivado -mode gui -nojournal -log open_bd.log -source "$ROOT/scripts/open_bd.tcl") > "$L/open_bd.out" 2>&1 & ;;
    schematic) (cd "$L" && exec vivado -mode gui -nojournal -log open_schematic.log -source "$ROOT/scripts/open_cfu_schematic.tcl") > "$L/open_schematic.out" 2>&1 & ;;
    dot4ins|irqdot4|irqcfu|getacc|fail) "$ROOT/scripts/open_waves.sh" "$v" > "$L/open_waves_$v.out" 2>&1 & ;;
    *) echo "unknown view: $v"; continue ;;
  esac
  echo "$! $v" >> "$L/open_view.pids"
  sleep 3
done
echo "opened on DISPLAY=$DISPLAY: $views (PIDs in $L/open_view.pids)"
echo "the XSim windows first run the simulation up to the event: dot4ins about 1 minute, the others a few minutes"
wait
