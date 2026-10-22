-- ================================================================================ --
-- NEORV32 CPU - ALU Custom Functions Unit (CFU): packed INT8 dot product            --
-- -------------------------------------------------------------------------------- --
-- Replaces the default XTEA example CFU of NEORV32 v1.13.6. Same entity, same      --
-- ports, so the rest of the CPU is unchanged.                                      --
--                                                                                  --
-- Two R-type instructions on the RISC-V "custom-0" opcode (0001011), funct7 = 0:   --
--   funct3 = 000  DOT4ACC rd, rs1, rs2                                             --
--                 acc <= acc + sum(i=0..3) int8(rs1[8i+7:8i]) * int8(rs2[8i+7:8i])  --
--                 rd  <= new acc (32-bit, wraps modulo 2^32 like C int32 maths)    --
--   funct3 = 001  SETACC  rd, rs1, x0                                              --
--                 acc <= rs1, rd <= rs1 (load the bias before a dot product)       --
-- Any other encoding never asserts valid_o, so the CPU raises an illegal           --
-- instruction exception after its CFU timeout (the repo's documented convention).  --
--                                                                                  --
-- Variant "3stage": valid_o 3 cycles after start_i for every instruction.        --
--   cycle 1: register the operands and the operation                              --
--   cycle 2: 4 signed 8x8 products, register the 4 products                       --
--   cycle 3: adder tree, add to acc, register acc                                 --
-- (The 2-stage version, rtl/neorv32_cpu_alu_cfu.vhd, does cycles 2 and 3 in one   --
--  cycle; it missed 300 MHz out of context, see the README.)                       --
-- The accumulator is internal state: it is not saved on a trap or context switch.  --
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

  -- decode --
  signal is_dot4, is_setacc : std_ulogic;

  -- stage 1: registered operands --
  signal s1_dot4, s1_setacc : std_ulogic;
  signal s1_a, s1_b         : std_ulogic_vector(31 downto 0);

  -- stage 2: registered products --
  type prod_t is array (0 to 3) of signed(15 downto 0);
  signal s2_dot4, s2_setacc : std_ulogic;
  signal s2_a               : std_ulogic_vector(31 downto 0);
  signal s2_p               : prod_t;

  -- stage 3: accumulator and done pulse --
  signal acc  : signed(31 downto 0);
  signal done : std_ulogic;

  -- combinational sum of the stage-2 products --
  signal dot4 : signed(31 downto 0);

begin

  -- Instruction Decode ---------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  is_dot4   <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) and (inst_i(31 downto 25) = "0000000") and
                        (inst_i(14 downto 12) = funct3_dot4_c) else '0';
  is_setacc <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) and (inst_i(31 downto 25) = "0000000") and
                        (inst_i(14 downto 12) = funct3_setacc_c) else '0';


  -- Packed INT8 Dot Product (4 lanes) ------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  dot4_comb: process(s2_p)
    variable sum : signed(17 downto 0); -- 4 * (-128 * -128) = 65536 needs 18 bits signed
  begin
    sum := (others => '0');
    for i in 0 to 3 loop
      sum := sum + resize(s2_p(i), 18);
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
      s1_a      <= (others => '0');
      s1_b      <= (others => '0');
      s2_dot4   <= '0';
      s2_setacc <= '0';
      s2_a      <= (others => '0');
      s2_p      <= (others => (others => '0'));
      acc       <= (others => '0');
      done      <= '0';
    elsif rising_edge(clk_i) then
      -- stage 1: capture operands of a valid instruction --
      s1_dot4   <= start_i and is_dot4;
      s1_setacc <= start_i and is_setacc;
      if (start_i = '1') then
        s1_a <= rs1_i;
        s1_b <= rs2_i;
      end if;
      -- stage 2: four signed 8x8 products --
      s2_dot4   <= s1_dot4;
      s2_setacc <= s1_setacc;
      s2_a      <= s1_a;
      for i in 0 to 3 loop
        s2_p(i) <= signed(s1_a(8*i+7 downto 8*i)) * signed(s1_b(8*i+7 downto 8*i));
      end loop;
      -- stage 3: update the accumulator --
      if (s2_setacc = '1') then
        acc <= signed(s2_a);
      elsif (s2_dot4 = '1') then
        acc <= acc + dot4; -- numeric_std "+" wraps modulo 2^32
      end if;
      done <= s2_dot4 or s2_setacc; -- single-cycle pulse
    end if;
  end process;

  result_o <= std_ulogic_vector(acc);
  valid_o  <= done;

end architecture;
