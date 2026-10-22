-- Extended unit testbench for the INT8 CFU with GETACC (and optionally SELBANK).
-- Copied from the combined project's tb/tb_cfu_int8.vhd (source_copies/tb/) and extended:
-- * the instruction word comes from the vector file (tb/gen_cfu_vectors_ext.py, an
--   independent Python model), so DOT4ACC, SETACC, GETACC, SELBANK and every illegal
--   encoding are defined by the model, not by the testbench;
-- * per-instruction counts of checked results.
-- Unchanged checks: one instruction at a time (stimulus and sampling on the falling edge),
-- result, latency (generic EXP_LAT, cycles from the start cycle to the valid cycle),
-- single-cycle valid pulse, and no valid for an illegal encoding (8 cycles watched).
-- Line format: <op> <inst> <rs1> <rs2> <expected>, all hex; op 7 = illegal.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

library neorv32;

entity tb_cfu_int8_ext is
  generic (
    EXP_LAT  : natural := 2;
    VEC_FILE : string  := "cfu_vectors.txt"
  );
end entity;

architecture sim of tb_cfu_int8_ext is
  constant t_c : time := 10 ns;
  signal clk, rstn, start, valid : std_ulogic := '0';
  signal inst, rs1, rs2, result : std_ulogic_vector(31 downto 0) := (others => '0');
  signal done_sim : boolean := false;
begin
  clk <= not clk after t_c / 2 when not done_sim;

  dut: entity neorv32.neorv32_cpu_alu_cfu
    port map (clk_i => clk, rstn_i => rstn, start_i => start, inst_i => inst,
              rs1_i => rs1, rs2_i => rs2, result_o => result, valid_o => valid);

  stim: process
    file fv : text open read_mode is VEC_FILE;
    variable l : line;
    variable op : std_ulogic_vector(3 downto 0);
    variable w, a, b, e : std_ulogic_vector(31 downto 0);
    variable n, n_err, n_ok, lat, n_ill : natural := 0;
    type cnt_t is array (0 to 3) of natural;
    variable ok_by : cnt_t := (others => 0);
  begin
    rstn <= '0';
    wait for 3 * t_c;
    wait until rising_edge(clk);
    rstn <= '1';
    wait until falling_edge(clk);
    while not endfile(fv) loop
      readline(fv, l);
      hread(l, op); hread(l, w); hread(l, a); hread(l, b); hread(l, e);
      n := n + 1;
      inst <= w; rs1 <= a; rs2 <= b; start <= '1';
      wait until falling_edge(clk);
      start <= '0'; inst <= (others => '0'); rs1 <= (others => 'X'); rs2 <= (others => 'X');
      if op = x"7" then
        n_ill := n_ill + 1;
        for i in 1 to 8 loop
          wait until falling_edge(clk);
          if valid = '1' then
            n_err := n_err + 1;
            report "vector " & integer'image(n) & ": valid asserted for an illegal encoding " & to_hstring(w) severity error;
          end if;
        end loop;
      else
        -- start was high in cycle 0; we are now in cycle 1. Count until valid is seen.
        lat := 1;
        while valid /= '1' and lat < 16 loop
          wait until falling_edge(clk);
          lat := lat + 1;
        end loop;
        if valid /= '1' then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": no valid within 16 cycles, inst " & to_hstring(w) severity error;
        elsif lat /= EXP_LAT then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": latency " & integer'image(lat) &  " cycles, expected " & integer'image(EXP_LAT) severity error;
        elsif result /= e then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": op " & to_hstring(op) & " result " & to_hstring(result) & " expected " & to_hstring(e) severity error;
        else
          n_ok := n_ok + 1;
          if to_integer(unsigned(op)) <= 3 then
            ok_by(to_integer(unsigned(op))) := ok_by(to_integer(unsigned(op))) + 1;
          end if;
        end if;
        wait until falling_edge(clk);
        if valid = '1' then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": valid longer than one cycle" severity error;
        end if;
      end if;
    end loop;
    report "CFU UNIT TB: vectors " & integer'image(n) & ", checked results " & integer'image(n_ok) &
           " (DOT4ACC " & integer'image(ok_by(0)) & ", SETACC " & integer'image(ok_by(1)) &
           ", GETACC " & integer'image(ok_by(2)) & ", SELBANK " & integer'image(ok_by(3)) &
           "), illegal encodings watched " & integer'image(n_ill) &
           ", errors " & integer'image(n_err) severity note;
    if n_err = 0 then
      report "CFU UNIT TB: PASS" severity note;
    else
      report "CFU UNIT TB: FAIL" severity error;
    end if;
    done_sim <= true;
    wait;
  end process;
end architecture;
