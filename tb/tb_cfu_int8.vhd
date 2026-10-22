-- Unit testbench for the INT8 dot-product CFU (rtl/neorv32_cpu_alu_cfu.vhd).
-- Reads tb/cfu_vectors.txt (from tb/gen_cfu_vectors.py, an independent Python model),
-- drives one instruction at a time (stimulus and sampling on the falling edge), and checks the result, the 2-cycle latency,
-- the latency (generic EXP_LAT), the single-cycle valid pulse, and that illegal encodings never assert valid.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

library neorv32;

entity tb_cfu_int8 is
  generic (EXP_LAT : natural := 2); -- cycles from the start cycle to the valid cycle
end entity;

architecture sim of tb_cfu_int8 is
  constant t_c : time := 10 ns;
  signal clk, rstn, start, valid : std_ulogic := '0';
  signal inst, rs1, rs2, result : std_ulogic_vector(31 downto 0) := (others => '0');
  signal done_sim : boolean := false;

  -- R-type word: funct7 | rs2 | rs1 | funct3 | rd | custom-0 (register numbers are don't-care here)
  function rtype(f7 : std_ulogic_vector(6 downto 0); f3 : std_ulogic_vector(2 downto 0)) return std_ulogic_vector is
  begin
    return f7 & "00010" & "00001" & f3 & "00011" & "0001011";
  end function;
begin
  clk <= not clk after t_c / 2 when not done_sim;

  dut: entity neorv32.neorv32_cpu_alu_cfu
    port map (clk_i => clk, rstn_i => rstn, start_i => start, inst_i => inst,
              rs1_i => rs1, rs2_i => rs2, result_o => result, valid_o => valid);

  stim: process
    file fv : text open read_mode is "cfu_vectors.txt";
    variable l : line;
    variable op : std_ulogic_vector(3 downto 0);
    variable a, b, e : std_ulogic_vector(31 downto 0);
    variable n, n_err, n_ok, lat : natural := 0;
    variable illegal_kind : natural := 0;
  begin
    rstn <= '0';
    wait for 3 * t_c;
    wait until rising_edge(clk);
    rstn <= '1';
    wait until falling_edge(clk);
    while not endfile(fv) loop
      readline(fv, l);
      hread(l, op); hread(l, a); hread(l, b); hread(l, e);
      n := n + 1;
      case op is
        when x"0" => inst <= rtype("0000000", "000");
        when x"1" => inst <= rtype("0000000", "001");
        when others => -- rotate through three illegal encodings
          case illegal_kind is
            when 0 => inst <= rtype("0000000", "010");        -- unused funct3
            when 1 => inst <= rtype("0000001", "000");        -- funct7 /= 0
            when others => inst <= x"0000302B" or rtype("0000000", "000"); -- custom-1 opcode bits set
          end case;
          illegal_kind := (illegal_kind + 1) mod 3;
      end case;
      rs1 <= a; rs2 <= b; start <= '1';
      wait until falling_edge(clk);
      start <= '0'; inst <= (others => '0'); rs1 <= (others => 'X'); rs2 <= (others => 'X');
      if op = x"7" then
        for i in 1 to 8 loop
          wait until falling_edge(clk);
          if valid = '1' then
            n_err := n_err + 1;
            report "vector " & integer'image(n) & ": valid asserted for an illegal encoding" severity error;
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
          report "vector " & integer'image(n) & ": no valid within 16 cycles" severity error;
        elsif lat /= EXP_LAT then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": latency " & integer'image(lat) &  " cycles, expected " & integer'image(EXP_LAT) severity error;
        elsif result /= e then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": result " & to_hstring(result) & " expected " & to_hstring(e) severity error;
        else
          n_ok := n_ok + 1;
        end if;
        wait until falling_edge(clk);
        if valid = '1' then
          n_err := n_err + 1;
          report "vector " & integer'image(n) & ": valid longer than one cycle" severity error;
        end if;
      end if;
    end loop;
    report "CFU UNIT TB: vectors " & integer'image(n) & ", checked results " & integer'image(n_ok) &
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
