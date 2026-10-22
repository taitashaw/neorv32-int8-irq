#!/usr/bin/env bash
# Builds the five XSim snapshots used by scripts/open_waves.sh (one folder per view),
# each in its own memory-capped scope. The snapshots are the verified images:
#   dot4ins, irqdot4, irqcfu, getacc : sim/images/dot4_getacc (final design: GETACC CFU, handler saves/restores the accumulator)
#   fail                     : sim/images/fail_crit100 (deliberate gate failure)
B=$(cd "$(dirname "$0")/.." && pwd)
for v in dot4ins irqdot4 irqcfu getacc; do
  [ -d "$B/sim/gui_$v" ] || "$B/scripts/build_gui_sim.sh" "$v" "$B/sim/images/dot4_getacc/neorv32_imem_image.vhd"
done
[ -d "$B/sim/gui_fail" ] || "$B/scripts/build_gui_sim.sh" fail "$B/sim/images/fail_crit100/neorv32_imem_image.vhd"
