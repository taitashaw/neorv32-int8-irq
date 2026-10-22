-- ================================================================================ --
-- NEORV32 CPU - ALU Custom Functions Unit (CFU): packed INT8 dot product            --
-- with an accumulator read-back instruction (GETACC)                               --
-- -------------------------------------------------------------------------------- --
-- Copy of the combined project's 2-stage CFU (rtl/neorv32_cpu_alu_cfu.vhd of        --
-- neorv32-int8-irq-combined) with one instruction added. Same entity, same ports, --
-- so the rest of the CPU is unchanged. DOT4ACC and SETACC keep their encodings     --
-- and their 2-cycle timing.                                                        --
--                                                                                  --
-- Three R-type instructions on the RISC-V "custom-0" opcode (0001011), funct7 = 0: --
--   funct3 = 000  DOT4ACC rd, rs1, rs2                                             --
--                 acc <= acc + sum(i=0..3) int8(rs1[8i+7:8i]) * int8(rs2[8i+7:8i])  --
--                 rd  <= new acc (32-bit, wraps modulo 2^32 like C int32 maths)    --
--   funct3 = 001  SETACC  rd, rs1, x0                                              --
--                 acc <= rs1, rd <= rs1 (load the bias before a dot product)       --
--   funct3 = 010  GETACC  rd, x0, x0   (NEW)                                       --
--                 rd  <= acc, acc unchanged (rs1 and rs2 are ignored)              --
--                 Used by a trap handler or a task switch to save the accumulator; --
--                 SETACC restores it.                                              --
-- Any other encoding never asserts valid_o, so the CPU raises an illegal           --
-- instruction exception after its CFU timeout (the repo's documented convention).  --
--                                                                                  --
-- Timing: 2 cycles from start_i to valid_o for every instruction.                  --
--   cycle 1: register the operands and the operation                              --
--   cycle 2: 4 signed 8x8 products, adder tree, add to acc, register acc          --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cpu_alu_cfu is
  port (
    -- global control --
    clk_i    : in  std_ulogic; -- global clock, rising edge
    rstn_i   : in  std_ulogic; -- global reset, low-active, async
    -- request --
    start_i  : in  std_ulogic;                     -- start trigger, single-shot
    inst_i   : in  std_ulogic_vector(31 downto 0); -- full instruction word
    rs1_i    : in  std_ulogic_vector(31 downto 0); -- register source operand 1
    rs2_i    : in  std_ulogic_vector(31 downto 0); -- register source operand 2
    -- response --
    result_o : out std_ulogic_vector(31 downto 0); -- operation result
    valid_o  : out std_ulogic                      -- operation done; result valid
  );
end entity;

architecture neorv32_cpu_alu_cfu_rtl of neorv32_cpu_alu_cfu is

  constant opcode_custom0_c : std_ulogic_vector(6 downto 0) := "0001011";
  constant funct3_dot4_c    : std_ulogic_vector(2 downto 0) := "000";
  constant funct3_setacc_c  : std_ulogic_vector(2 downto 0) := "001";
  constant funct3_getacc_c  : std_ulogic_vector(2 downto 0) := "010";

  -- decode --
  signal is_dot4, is_setacc, is_getacc : std_ulogic;

  -- stage 1: registered operands --
  signal s1_dot4, s1_setacc, s1_getacc : std_ulogic;
  signal s1_a, s1_b                    : std_ulogic_vector(31 downto 0);

  -- stage 2: accumulator and done pulse --
  signal acc  : signed(31 downto 0);
  signal done : std_ulogic;

  -- combinational dot product of the stage-1 operands --
  signal dot4 : signed(31 downto 0);

begin

  -- Instruction Decode ---------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  is_dot4   <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) and (inst_i(31 downto 25) = "0000000") and
                        (inst_i(14 downto 12) = funct3_dot4_c) else '0';
  is_setacc <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) and (inst_i(31 downto 25) = "0000000") and
                        (inst_i(14 downto 12) = funct3_setacc_c) else '0';
  is_getacc <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) and (inst_i(31 downto 25) = "0000000") and
                        (inst_i(14 downto 12) = funct3_getacc_c) else '0';


  -- Packed INT8 Dot Product (4 lanes) ------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  dot4_comb: process(s1_a, s1_b)
    variable sum : signed(17 downto 0); -- 4 * (-128 * -128) = 65536 needs 18 bits signed
  begin
    sum := (others => '0');
    for i in 0 to 3 loop
      sum := sum + resize(signed(s1_a(8*i+7 downto 8*i)) * signed(s1_b(8*i+7 downto 8*i)), 18);
    end loop;
    dot4 <= resize(sum, 32);
  end process;


  -- Pipeline -------------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  pipe: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      s1_dot4   <= '0';
      s1_setacc <= '0';
      s1_getacc <= '0';
      s1_a      <= (others => '0');
      s1_b      <= (others => '0');
      acc       <= (others => '0');
      done      <= '0';
    elsif rising_edge(clk_i) then
      -- stage 1: capture operands of a valid instruction --
      s1_dot4   <= start_i and is_dot4;
      s1_setacc <= start_i and is_setacc;
      s1_getacc <= start_i and is_getacc;
      if (start_i = '1') then
        s1_a <= rs1_i;
        s1_b <= rs2_i;
      end if;
      -- stage 2: update the accumulator (GETACC leaves it unchanged) --
      if (s1_setacc = '1') then
        acc <= signed(s1_a);
      elsif (s1_dot4 = '1') then
        acc <= acc + dot4; -- numeric_std "+" wraps modulo 2^32
      end if;
      done <= s1_dot4 or s1_setacc or s1_getacc; -- single-cycle pulse
    end if;
  end process;

  result_o <= std_ulogic_vector(acc); -- DOT4ACC: new acc, SETACC: rs1 (= new acc), GETACC: acc
  valid_o  <= done;

end architecture;
