#!/usr/bin/env bash
# out-of-context builds of int8_irq_top, one at a time (each in its own 16 GB memory-capped scope)
B=$(cd "$(dirname "$0")/.." \&\& pwd)
IMG=$B/impl/imem_image_for_impl.vhd
for f in 100 200 300; do
  $B/scripts/run_ooc.sh cfu_mon true true $f $IMG
done
$B/scripts/run_ooc.sh cfu3_mon true true 300 $IMG $B/rtl/neorv32_cpu_alu_cfu_3stage.vhd
for f in 100 200 300; do
  $B/scripts/run_ooc.sh nocfu_nomon false false $f $IMG
done
echo "ALL_OOC_DONE $(date -u +%FT%TZ)"
