#!/usr/bin/env bash
# Usage: run_sim.sh <run_name> <imem_image.vhd> [max_time] [vcd_tcl]
# Adapted from the profiler project's scripts/run_sim.sh. Compiles the NEORV32 core
# (official file order, IMEM image swapped, default XTEA CFU swapped for the INT8 CFU),
# the XBUS helpers from neorv32/sim, the monitor, the combined top and the testbench
# with xvhdl --2008, elaborates int8_irq_tb and runs until the software signals DONE
# (std.env.finish) or max_time.
# env CFU=<cfu source>      (default rtl/neorv32_cpu_alu_cfu.vhd, the 2-stage CFU)
# env XGEN="-generic_top ICACHE_EN=false ..."  extra testbench generics
# env DEBUG=typical|all     elaboration debug level (default off, typical with a vcd tcl)
# If a 4th argument is given, it is sourced as Tcl before "run" (used for VCD dumps).
set -e
B=$(cd "$(dirname "$0")/.." \&\& pwd)
R=$B/neorv32
NAME=$1; IMG=$2; T=${3:-200ms}; VCDTCL=$4
CFU=${CFU:-$B/rtl/neorv32_cpu_alu_cfu.vhd}
W=$B/sim/run_$NAME
[ -e "$W" ] && mv "$W" "$W.old_$(date +%s)"   # move an old run aside, never rm on a variable
mkdir -p "$W"; cd "$W"
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH  # settings64.sh is not present in this install
sed "s#\$NEORV32_HOME#$R#" $R/rtl/file_list_core.f \
 | sed "s#$R/rtl/core/neorv32_imem_image.vhd#$IMG#" \
 | sed "s#$R/rtl/core/neorv32_cpu_alu_cfu.vhd#$CFU#" > files.f
grep -q "$CFU" files.f || { echo "CFU swap failed"; exit 2; }
for f in xbus_gateway xbus_memory; do echo "$R/sim/$f.vhd" >> files.f; done
echo "$B/rtl/irq_lat_mon.vhd" >> files.f
echo "$B/rtl/int8_irq_top.vhd" >> files.f
echo "$B/sim/int8_irq_tb.vhd"  >> files.f
cp "$IMG" ./imem_image_used.vhd
echo "== cfu source: $CFU"
echo "== xvhdl $(date -u +%FT%TZ)"
xvhdl --2008 -work neorv32 -f files.f
DBG=${DEBUG:-off}; [ -n "$VCDTCL" ] && [ -z "$DEBUG" ] && DBG="typical"
echo "== xelab $(date -u +%FT%TZ) debug=$DBG generics: $XGEN"
xelab --debug $DBG -L neorv32 $XGEN neorv32.int8_irq_tb -s tb_snap
{ [ -n "$VCDTCL" ] && echo "source $VCDTCL"; echo "run $T"; echo "quit"; } > run.tcl
echo "== xsim run start $(date -u +%FT%TZ)"
xsim tb_snap -t run.tcl -onerror quit < /dev/null
echo "== xsim done $(date -u +%FT%TZ)"
