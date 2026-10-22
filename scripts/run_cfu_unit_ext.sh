#!/usr/bin/env bash
# Unit test of one INT8 CFU source with the extended testbench (adapted from scripts/run_cfu_unit_tb.sh): NEORV32 package + CFU source + tb_cfu_int8_ext.
# usage: run_cfu_unit_ext.sh <run_name> <cfu_source.vhd> <expected_latency_cycles> <vector_file>
set -e
G=$(cd "$(dirname "$0")/.." \&\& pwd)
NAME=$1; CFU=$2; LAT=$3; VEC=$4
W=$G/tb/run_$NAME
[ -e "$W" ] && mv "$W" "$W.old_$(date +%s)"  # move an old run aside, never rm on a variable
mkdir -p "$W"; cd "$W"
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
cp "$VEC" ./vectors.txt
echo "== cfu source: $CFU  vectors: $VEC  expected latency: $LAT  $(date -u +%FT%TZ)"
sha256sum "$CFU" "$VEC"
xvhdl --2008 -work neorv32 $G/neorv32/rtl/core/neorv32_package.vhd "$CFU" $G/tb/tb_cfu_int8_ext.vhd
xelab --debug typical -L neorv32 neorv32.tb_cfu_int8_ext -s tb_cfu -generic_top EXP_LAT=$LAT -generic_top VEC_FILE=vectors.txt
printf 'run all\nquit\n' > run.tcl
xsim tb_cfu -t run.tcl
echo "== done $(date -u +%FT%TZ)"
