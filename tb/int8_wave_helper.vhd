-- Viewing helper for the XSim waveform (scripts/waves_view.tcl). Simulation only.
-- It adds NO logic to the design. It reads the INT8 CFU's own signals inside the official
-- NEORV32 testbench through VHDL-2008 external names and turns them into easy-to-read rows:
--   * the instruction name (DOT4ACC / SETACC) on the cycle the CPU starts the CFU
--   * the four signed byte lanes of each operand (from the CFU's stage-1 registers s1_a, s1_b)
--   * the four lane products (the CFU itself sums them inside one process variable, so they
--     are not separate wires in the CFU; they are recomputed here from the same registers)
--   * a clock-tick counter from "go" (start_i) to "answer ready" (valid_o)
-- A check compares the helper's four products with the CFU's own sum (signal dot4) on every
-- DOT4ACC and reports an error if they ever differ.
-- Instantiated by tb/int8_wave_top.vhd next to the testbench instance "tb".
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity int8_wave_helper is
end entity;

architecture sim of int8_wave_helper is

  alias cfu_clk    is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.clk_i     : std_ulogic >>;
  alias cfu_start  is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.start_i   : std_ulogic >>;
  alias cfu_inst   is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.inst_i    : std_ulogic_vector(31 downto 0) >>;
  alias cfu_valid  is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.valid_o   : std_ulogic >>;
  alias cfu_s1_a   is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.s1_a      : std_ulogic_vector(31 downto 0) >>;
  alias cfu_s1_b   is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.s1_b      : std_ulogic_vector(31 downto 0) >>;
  alias cfu_s1_dot is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.s1_dot4   : std_ulogic >>;
  alias cfu_dot4   is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.dot4      : signed(31 downto 0) >>;
  alias cfu_is_dot is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.is_dot4   : std_ulogic >>;
  alias cfu_is_set is << signal .int8_wave_top.tb.neorv32_top_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cpu_alu_cfu_enabled.cpu_alu_cfu_inst.is_setacc : std_ulogic >>;

  type op_t is (none, DOT4ACC, SETACC, OTHER);
  signal instruction : op_t := none;

  subtype byte_t is integer range -128 to 127;
  signal a0, a1, a2, a3 : byte_t := 0; -- rs1 lanes (weights in the program)
  signal b0, b1, b2, b3 : byte_t := 0; -- rs2 lanes (activations in the program)
  signal p0, p1, p2, p3 : integer range -16256 to 16384 := 0;
  signal ticks_since_go : natural := 0;
  signal checks_done, check_errors : natural := 0;

  function lane(w : std_ulogic_vector(31 downto 0); i : natural) return integer is
  begin
    return to_integer(signed(w(8*i+7 downto 8*i)));
  end function;

begin

  instruction <= DOT4ACC when (cfu_start = '1') and (cfu_is_dot = '1') else
                 SETACC  when (cfu_start = '1') and (cfu_is_set = '1') else
                 OTHER   when (cfu_start = '1') else
                 none;

  a0 <= lane(cfu_s1_a, 0); a1 <= lane(cfu_s1_a, 1); a2 <= lane(cfu_s1_a, 2); a3 <= lane(cfu_s1_a, 3);
  b0 <= lane(cfu_s1_b, 0); b1 <= lane(cfu_s1_b, 1); b2 <= lane(cfu_s1_b, 2); b3 <= lane(cfu_s1_b, 3);
  p0 <= a0 * b0; p1 <= a1 * b1; p2 <= a2 * b2; p3 <= a3 * b3;

  -- clock ticks counted from the edge that sees start_i: 1, 2, ... The count stays on screen
  -- while valid_o is high and goes back to 0 on the next edge.
  tick_counter: process(cfu_clk)
    variable running : boolean := false;
  begin
    if rising_edge(cfu_clk) then
      if cfu_start = '1' then
        ticks_since_go <= 1;
        running := true;
      elsif running then
        if cfu_valid = '1' then
          running := false;
          ticks_since_go <= 0;
        else
          ticks_since_go <= ticks_since_go + 1;
        end if;
      end if;
    end if;
  end process;

  -- the helper's products must add up to the CFU's own sum on every DOT4ACC
  self_check: process(cfu_clk)
  begin
    if rising_edge(cfu_clk) then
      if cfu_s1_dot = '1' then
        checks_done <= checks_done + 1;
        if to_integer(cfu_dot4) /= (lane(cfu_s1_a,0)*lane(cfu_s1_b,0) + lane(cfu_s1_a,1)*lane(cfu_s1_b,1) +
                                    lane(cfu_s1_a,2)*lane(cfu_s1_b,2) + lane(cfu_s1_a,3)*lane(cfu_s1_b,3)) then
          check_errors <= check_errors + 1;
          report "int8_wave_helper: lane products do not add up to the CFU dot4 sum" severity error;
        end if;
      end if;
    end if;
  end process;

end architecture;
