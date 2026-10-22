#!/usr/bin/env bash
# CFU unit runs for the GETACC CFU (21 Oct): the final CFU and two mutants that must be caught.
G=$(cd "$(dirname "$0")/.." \&\& pwd)
S=$G/scripts/run_cfu_unit_ext.sh
L=$G/sim/logs
V=$G/tb/cfu_vectors_getacc.txt
$S getacc    $G/rtl/neorv32_cpu_alu_cfu.vhd             2 $V > $L/cfu_unit_ext_getacc.log 2>&1
$S getacc_m1 $G/tb/mutant/getacc_m1_offby1.vhd          2 $V > $L/cfu_unit_ext_getacc_m1_offby1.log 2>&1
$S getacc_m2 $G/tb/mutant/getacc_m2_getacc_clears.vhd   2 $V > $L/cfu_unit_ext_getacc_m2_getacc_clears.log 2>&1
echo "UNIT_GETACC_DONE $(date -u +%FT%TZ)"
