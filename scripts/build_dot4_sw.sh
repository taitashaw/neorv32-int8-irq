#!/usr/bin/env bash
# Build one variant of the DOT4 program (sw/dot4_irq) in its own fresh folder sw/build_<name>/
# (no make clean, nothing deleted) and copy the image and ELF to sim/images/<name>/.
# usage: build_dot4_sw.sh <name> <HANDLER_TOUCHES_CFU 0|1> <CFU_SAVE 0|1> [N_IRQ (default 2000)]
#   dot4_getacc  1 1 : final design, the handler uses the CFU and saves/restores the accumulator
#   dot4_clobber 1 0 : the handler uses the CFU and saves nothing (negative control)
#   dot4_final   0 0 : the handler does not touch the CFU (the first combined run)
set -e
B=$(cd "$(dirname "$0")/.." \&\& pwd)
NAME=$1; HT=$2; CS=$3; N=${4:-2000}
D=$B/sw/build_$NAME
[ -e "$D" ] && mv "$D" "$D.old_$(date +%s)"
mkdir -p "$D"
cp $B/sw/dot4_irq/main.c $B/sw/dot4_irq/dot4_stress.S $B/sw/dot4_irq/Makefile "$D"/
export PATH=/tools/Xilinx/2025.2/gnu/riscv/lin/bin:$PATH
echo "== build $NAME: N_IRQ=$N HANDLER_TOUCHES_CFU=$HT CFU_SAVE=$CS $(date -u +%FT%TZ)"
make -C "$D" RISCV_PREFIX=riscv64-unknown-elf- N_IRQ=$N HANDLER_TOUCHES_CFU=$HT CFU_SAVE=$CS image
I=$B/sim/images/$NAME
[ -e "$I" ] && mv "$I" "$I.old_$(date +%s)"
mkdir -p "$I"
cp "$D/neorv32_imem_image.vhd" "$D/main.elf" "$I"/
riscv64-unknown-elf-objdump -d "$D/main.elf" > $B/sim/logs/${NAME}_disasm.txt
riscv64-unknown-elf-size "$D/main.elf"
