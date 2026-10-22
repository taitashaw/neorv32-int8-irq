#!/usr/bin/env bash
# usage: run_ooc.sh <tag> <cfu true|false> <mon true|false> <freq_mhz> <imem_image.vhd> [cfu_source.vhd]
# one Vivado batch run in impl/<tag>_<f>mhz/
B=$(cd "$(dirname "$0")/.." \&\& pwd)
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
TAG=$1; CFU=$2; MON=$3; F=$4; IMG=$5; SRC=${6:-$B/rtl/neorv32_cpu_alu_cfu.vhd}
O=$B/impl/${TAG}_${F}mhz
mkdir -p $O; cd $O
echo "start $(date -u +%FT%TZ)" > $O/wall.txt
vivado -mode batch -nojournal -log $O/vivado_console.log -source $B/scripts/ooc_combined.tcl -tclargs $CFU $MON $F $O $IMG $SRC > /dev/null 2>&1
echo "rc=$? end $(date -u +%FT%TZ)" >> $O/wall.txt
