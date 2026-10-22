-- Waveform top: the official NEORV32 testbench (sim/neorv32_tb.vhd) with exactly the generic
-- values of the verified CFU run (logs/xsim_int8_cfu.log, "-generic_top" list), plus the
-- viewing helper tb/int8_wave_helper.vhd. Simulation only. A wrapper is needed because
-- xelab ignores -generic_top when there is more than one top level unit.
library ieee;
use ieee.std_logic_1164.all;

library neorv32;

entity int8_wave_top is
end entity;

architecture sim of int8_wave_top is
begin

  tb: entity neorv32.neorv32_tb
    generic map (
      DUAL_CORE_EN      => false,
      JTAG_TESTS_EN     => false,
      TRACE_LOG_EN      => false,
      RISCV_ISA_C       => true,
      RISCV_ISA_E       => false,
      RISCV_ISA_M       => true,
      RISCV_ISA_U       => false,
      RISCV_ISA_Zaamo   => false,
      RISCV_ISA_Zalrsc  => false,
      RISCV_ISA_Zba     => false,
      RISCV_ISA_Zbb     => false,
      RISCV_ISA_Zbc     => false,
      RISCV_ISA_Zbkb    => false,
      RISCV_ISA_Zbkc    => false,
      RISCV_ISA_Zbkx    => false,
      RISCV_ISA_Zbs     => false,
      RISCV_ISA_Zcb     => false,
      RISCV_ISA_Zcmop   => false,
      RISCV_ISA_Zfinx   => false,
      RISCV_ISA_Zibi    => false,
      RISCV_ISA_Zicntr  => true,
      RISCV_ISA_Zicond  => false,
      RISCV_ISA_Zihpm   => false,
      RISCV_ISA_Zimop   => false,
      RISCV_ISA_Zknd    => false,
      RISCV_ISA_Zkne    => false,
      RISCV_ISA_Zknh    => false,
      RISCV_ISA_Zksed   => false,
      RISCV_ISA_Zksh    => false,
      RISCV_ISA_Zmmul   => false,
      RISCV_ISA_Xcfu    => true,
      CPU_FAST_MUL_EN   => true,
      CPU_FAST_MUL_REGS => 1,
      CPU_FAST_SHIFT_EN => true,
      ICACHE_EN         => false,
      DCACHE_EN         => false,
      IMEM_SIZE         => 32768,
      DMEM_SIZE         => 8192
    );

  helper: entity neorv32.int8_wave_helper;

end architecture;
