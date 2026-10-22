#!/usr/bin/env bash
# Usage: run_official_tb.sh <run_name> <imem_image.vhd> <sim_time e.g. 30ms> [cfu_source.vhd]
# Adapted from the INT8 project's scripts/run_soc_sim.sh: the official NEORV32 testbench
# (sim/neorv32_tb.vhd) in XSim, VHDL-2008, IMEM image swapped, XTEA CFU swapped for the
# INT8 CFU, and the testbench generics set to the COMBINED configuration as far as the
# official testbench allows (it fixes OCD, PMP, Smcntrpmf, DMEM_OUTREG_EN and its own
# peripherals; see the README).
# env ICACHE=true|false (default true): i-cache with 4 blocks of 64 bytes as in the combined top
set -e
B=$(cd "$(dirname "$0")/.." \&\& pwd)
R=$B/neorv32
NAME=$1; IMG=$2; T=$3; CFU=${4:-$B/rtl/neorv32_cpu_alu_cfu.vhd}
IC=${ICACHE:-true}
W=$B/sim/run_$NAME
[ -e "$W" ] && mv "$W" "$W.old_$(date +%s)"   # move an old run aside, never rm on a variable
mkdir -p "$W"; cd "$W"
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
sed "s#\$NEORV32_HOME#$R#" $R/rtl/file_list_core.f \
 | sed "s#$R/rtl/core/neorv32_imem_image.vhd#$IMG#" \
 | sed "s#$R/rtl/core/neorv32_cpu_alu_cfu.vhd#$CFU#" > files.f
for f in jtag_dmi_pkg sim_uart_rx xbus_memory xbus_gateway xbus_fmem psram_model neorv32_tb; do echo "$R/sim/$f.vhd" >> files.f; done
grep "alu_cfu" files.f
G=""
for g in DUAL_CORE_EN=false JTAG_TESTS_EN=false TRACE_LOG_EN=false \
         RISCV_ISA_C=true RISCV_ISA_E=false RISCV_ISA_M=true RISCV_ISA_U=false \
         RISCV_ISA_Zaamo=false RISCV_ISA_Zalrsc=false RISCV_ISA_Zba=false RISCV_ISA_Zbb=false \
         RISCV_ISA_Zbc=false RISCV_ISA_Zbkb=false RISCV_ISA_Zbkc=false RISCV_ISA_Zbkx=false \
         RISCV_ISA_Zbs=false RISCV_ISA_Zcb=false RISCV_ISA_Zcmop=false RISCV_ISA_Zfinx=false \
         RISCV_ISA_Zibi=false RISCV_ISA_Zicntr=true RISCV_ISA_Zicond=false RISCV_ISA_Zihpm=false \
         RISCV_ISA_Zimop=false RISCV_ISA_Zknd=false RISCV_ISA_Zkne=false RISCV_ISA_Zknh=false \
         RISCV_ISA_Zksed=false RISCV_ISA_Zksh=false RISCV_ISA_Zmmul=false RISCV_ISA_Xcfu=true \
         CPU_FAST_MUL_EN=true CPU_FAST_MUL_REGS=1 CPU_FAST_SHIFT_EN=true \
         ICACHE_EN=$IC ICACHE_NUM_BLOCKS=4 CACHE_BLOCK_SIZE=64 DCACHE_EN=false \
         IMEM_SIZE=32768 DMEM_SIZE=8192; do
  G="$G -generic_top $g"
done
echo "== xvhdl $(date -u +%FT%TZ)"
xvhdl --2008 -work neorv32 -f files.f
echo "== xelab $(date -u +%FT%TZ) generics:$G"
xelab --debug off -L neorv32 neorv32.neorv32_tb -s tb_snap $G
printf 'run %s\nquit\n' "$T" > run.tcl
echo "== xsim run $T start $(date -u +%FT%TZ)"
xsim tb_snap -t run.tcl
echo "== xsim done $(date -u +%FT%TZ)"
