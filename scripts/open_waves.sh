#!/usr/bin/env bash
# XSim waveform window for one view, on $DISPLAY (default :0), no auto-quit.
# Usage: scripts/open_waves.sh [dot4ins|irqdot4|irqcfu|getacc|fail]   (default irqdot4)
#   dot4ins : one DOT4ACC instruction in the combined design (CFU story groups)
#   irqdot4 : worst-case interrupt of the DOT4 scenario (74 cycles, gate PASS, bound 133)
#   irqcfu  : worst interrupt that fired inside a DOT4ACC instruction
#   getacc  : the same interrupt through the whole handler: GETACC saves the running total, SETACC restores it
#   fail    : the deliberate gate failure (CRIT_N = 100, 905 cycles > bound 521)
# Each view has its own snapshot folder sim/gui_<view> (scripts/build_gui_sim.sh), so
# several views can be open at the same time. The simulation runs in the GUI up to the
# event first: about 1 minute for dot4ins, 3 to 6 minutes for the others.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
export DISPLAY=${DISPLAY:-:0}
export VIEW=${1:-irqdot4}
case "$VIEW" in
  dot4ins|irqdot4|irqcfu|getacc|fail) SIMDIR=$ROOT/sim/gui_$VIEW ;;
  *) echo "usage: $0 [dot4ins|irqdot4|irqcfu|getacc|fail]"; exit 2 ;;
esac
if [ ! -d "$SIMDIR/xsim.dir/tb_snap" ]; then
  echo "snapshot missing: $SIMDIR (build it with scripts/build_gui_sim.sh, see scripts/make_gui_snapshots.sh)"; exit 1
fi
cd "$SIMDIR"
exec xsim tb_snap -gui -wdb "tb_snap_$VIEW.wdb" -log "xsim_gui_$VIEW.log" -tclbatch "$ROOT/scripts/waves_view.tcl"
