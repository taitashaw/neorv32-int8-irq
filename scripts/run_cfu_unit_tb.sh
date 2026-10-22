#!/usr/bin/env bash
# Unit test of an INT8 CFU alone: NEORV32 package + CFU source + tb_cfu_int8, run to the end.
# usage: run_cfu_unit_tb.sh <run_name> <cfu_source.vhd> <expected_latency_cycles>
set -e
B=$(cd "$(dirname "$0")/.." \&\& pwd)
NAME=$1; CFU=$2; LAT=$3
W=$B/tb/run_$NAME
[ -e "$W" ] && mv "$W" "$W.old_$(date +%s)"  # move an old run aside, never rm on a variable
mkdir -p "$W"; cd "$W"
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
cp $B/tb/cfu_vectors.txt .
xvhdl --2008 -work neorv32 $B/neorv32/rtl/core/neorv32_package.vhd $CFU $B/tb/tb_cfu_int8.vhd
xelab --debug typical -L neorv32 neorv32.tb_cfu_int8 -s tb_cfu -generic_top EXP_LAT=$LAT
cat > run.tcl <<TCL
run all
quit
TCL
xsim tb_cfu -t run.tcl
