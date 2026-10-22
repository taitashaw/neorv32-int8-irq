#!/usr/bin/env bash
# Usage: build_gui_sim.sh <name> <imem_image.vhd>
# Builds an XSim snapshot for the waveform views (GUI). Same file list, same compile
# order and same testbench as scripts/run_sim.sh (the runs in the README), with
# PROBE_EN = true (as in the VCD replays) and the viewing helper, both inside
# tb/int8irq_wave_top.vhd, and "--debug typical" so internal signals can be shown.
# It does not run the simulation; scripts/open_waves.sh does that in the XSim GUI.
# Output folder: sim/gui_<name>/ (created new; the script stops if it exists).
# Adapted from the profiler project's scripts/build_gui_sim.sh.
set -euo pipefail
B=$(cd "$(dirname "$0")/.." \&\& pwd)
R=$B/neorv32
NAME=$1; IMG=$2
CFU=$B/rtl/neorv32_cpu_alu_cfu.vhd
W=$B/sim/gui_$NAME
if [ -e "$W" ]; then echo "exists: $W (move it away by hand to rebuild)"; exit 1; fi
mkdir -p "$W"; cd "$W"
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
sed "s#\$NEORV32_HOME#$R#" $R/rtl/file_list_core.f \
 | sed "s#$R/rtl/core/neorv32_imem_image.vhd#$IMG#" \
 | sed "s#$R/rtl/core/neorv32_cpu_alu_cfu.vhd#$CFU#" > files.f
grep -q "$CFU" files.f || { echo "CFU swap failed"; exit 2; }
for f in xbus_gateway xbus_memory; do echo "$R/sim/$f.vhd" >> files.f; done
echo "$B/rtl/irq_lat_mon.vhd"          >> files.f
echo "$B/rtl/int8_irq_top.vhd"         >> files.f
echo "$B/sim/int8_irq_tb.vhd"          >> files.f
echo "$B/tb/int8irq_wave_helper.vhd"   >> files.f
echo "$B/tb/int8irq_wave_top.vhd"      >> files.f
cp "$IMG" ./imem_image_used.vhd
echo "== xvhdl $(date -u +%FT%TZ)"
xvhdl --2008 -work neorv32 -f files.f > xvhdl_console.log
echo "== xelab $(date -u +%FT%TZ) debug=typical top=int8irq_wave_top"
xelab --debug typical -L neorv32 neorv32.int8irq_wave_top -s tb_snap > xelab_console.log
echo "== done $(date -u +%FT%TZ) snapshot tb_snap in $W"
