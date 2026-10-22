-- ================================================================================ --
-- irq_lat_mon: interrupt-latency monitor for the NEORV32 RISC-V processor           --
-- -------------------------------------------------------------------------------- --
-- Measures, in clock cycles, the time from an interrupt request line rising to the  --
-- moment the CPU reports the first instruction of its trap handler as completed on  --
-- the NEORV32 execution trace port (trace_port_t: valid = 1 and intr = 1).          --
--                                                                                  --
-- Definition (edge counting):                                                      --
--   k = first rising clock edge at which req_i is sampled '1' (it was '0' before)   --
--   m = first rising clock edge after k at which the trace port shows               --
--       valid = '1' and intr = '1'                                                  --
--   latency L = m - k  (cycles)                                                     --
-- The latency is split into two parts using the same trace port:                    --
--   drain L_a = c - k, where c is the edge of the last ordinary instruction commit  --
--               (valid = '1', intr = '0') seen between k and m (0 if none)          --
--   entry L_b = m - c  (trap entry, handler fetch, first handler instruction)      --
--                                                                                  --
-- Statistics kept in hardware: count, min, max, sum, last, max entry part, number  --
-- of samples above a software-set bound (and a sticky flag), a 16-bin histogram    --
-- with a software-set bin width of 2^SHIFT cycles, responses without a request     --
-- ("orphan") and new requests while one is still pending ("overrun").              --
--                                                                                  --
-- Bus: NEORV32 XBUS (Wishbone-style, stb is a one-cycle pulse, ack one cycle later) --
-- Register map (byte offsets, 32-bit words):                                       --
--   0x00 CTRL   W: bit 0 = clear statistics, bits 11:8 = histogram SHIFT            --
--               R: bit 0 = measurement pending, bit 1 = bound violated (sticky),    --
--                  bit 2 = histogram clear in progress (16 cycles), bits 11:8 SHIFT --
--   0x04 BOUND  RW: latency bound in cycles (a sample above it is a violation)      --
--   0x08 COUNT  R   0x0C MIN  R   0x10 MAX  R   0x14 SUM  R   0x18 LAST  R          --
--   0x1C NVIOL  R: number of samples with L > BOUND                                 --
--   0x20 ERRS   R: bits 15:0 orphan responses, bits 31:16 overruns                  --
--   0x24 TAG    RW: free scenario tag (also copied into the sample output)          --
--   0x28 MAXB   R: largest entry part L_b seen                                      --
--   0x40 to 0x7C HIST(0) to HIST(15) R: bin i counts samples with                  --
--               min(L >> SHIFT, 15) = i                                             --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity irq_lat_mon is
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;
    -- measurement points --
    req_i       : in  std_ulogic;   -- interrupt request line as seen by the CPU
    trace_i     : in  trace_port_t; -- NEORV32 CPU execution trace port
    -- bus slave --
    xbus_req_i  : in  xbus_req_t;
    xbus_rsp_o  : out xbus_rsp_t;
    -- status --
    viol_o      : out std_ulogic;   -- sticky: a sample exceeded BOUND
    -- per-sample output for testbench logging (unused in hardware, trimmed by synthesis) --
    smp_valid_o : out std_ulogic;
    smp_lat_o   : out std_ulogic_vector(31 downto 0);
    smp_drain_o : out std_ulogic_vector(31 downto 0);
    smp_tag_o   : out std_ulogic_vector(31 downto 0)
  );
end entity;

architecture irq_lat_mon_rtl of irq_lat_mon is

  constant nbins_c : natural := 16;
  type hist_t is array (0 to nbins_c-1) of unsigned(31 downto 0);
  -- histogram lives in distributed RAM: one write port, two asynchronous read ports --
  signal hist     : hist_t := (others => (others => '0'));
  signal h_we     : std_ulogic;                 -- increment pending for bin h_bin
  signal h_bin    : unsigned(3 downto 0);
  signal h_clr    : std_ulogic;                 -- clear sequence running
  signal h_clr_a  : unsigned(3 downto 0);
  signal h_raddr  : unsigned(3 downto 0);       -- bus read address
  signal h_rdata  : unsigned(31 downto 0);

  -- measurement --
  signal req_q   : std_ulogic;
  signal pend    : std_ulogic;
  signal cnt     : unsigned(31 downto 0); -- cycles since request edge, minus 1
  signal drain   : unsigned(31 downto 0); -- L_a of the running measurement
  signal resp    : std_ulogic;
  signal commit  : std_ulogic;

  -- statistics --
  signal st_count, st_min, st_max, st_sum, st_last, st_nviol, st_maxb : unsigned(31 downto 0);
  signal st_orphan, st_overrun : unsigned(15 downto 0);
  signal st_viol  : std_ulogic;
  signal bound    : unsigned(31 downto 0);
  signal shift    : unsigned(3 downto 0);
  signal tag      : std_ulogic_vector(31 downto 0);
  signal clr      : std_ulogic;

  -- bus --
  signal ack   : std_ulogic;
  signal rdata : std_ulogic_vector(31 downto 0);

  function bin_f(lat : unsigned(31 downto 0); sh : unsigned(3 downto 0)) return unsigned is
    variable v : unsigned(31 downto 0);
  begin
    v := shift_right(lat, to_integer(sh));
    if (v > nbins_c-1) then
      return to_unsigned(nbins_c-1, 4);
    else
      return v(3 downto 0);
    end if;
  end function;

begin

  resp   <= trace_i.valid and trace_i.intr;
  commit <= trace_i.valid and (not trace_i.intr);

  -- Measurement and statistics ----------------------------------------------------------
  measure: process(rstn_i, clk_i)
    variable lat_v, lb_v : unsigned(31 downto 0);
  begin
    if (rstn_i = '0') then
      req_q      <= '0';
      pend       <= '0';
      cnt        <= (others => '0');
      drain      <= (others => '0');
      st_count   <= (others => '0');
      st_min     <= (others => '1');
      st_max     <= (others => '0');
      st_sum     <= (others => '0');
      st_last    <= (others => '0');
      st_nviol   <= (others => '0');
      st_maxb    <= (others => '0');
      st_orphan  <= (others => '0');
      st_overrun <= (others => '0');
      st_viol    <= '0';
      h_we       <= '0';
      h_bin      <= (others => '0');
      h_clr      <= '0';
      h_clr_a    <= (others => '0');
      smp_valid_o <= '0';
      smp_lat_o   <= (others => '0');
      smp_drain_o <= (others => '0');
    elsif rising_edge(clk_i) then
      req_q       <= req_i;
      smp_valid_o <= '0';
      h_we        <= '0';
      -- histogram clear sequencer: one bin per cycle --
      if (h_clr = '1') then
        h_clr_a <= h_clr_a + 1;
        if (h_clr_a = nbins_c-1) then
          h_clr <= '0';
        end if;
      end if;

      if (clr = '1') then
        pend       <= '0';
        st_count   <= (others => '0');
        st_min     <= (others => '1');
        st_max     <= (others => '0');
        st_sum     <= (others => '0');
        st_last    <= (others => '0');
        st_nviol   <= (others => '0');
        st_maxb    <= (others => '0');
        st_orphan  <= (others => '0');
        st_overrun <= (others => '0');
        st_viol    <= '0';
        h_clr      <= '1';
        h_clr_a    <= (others => '0');
      elsif (pend = '1') then
        if (resp = '1') then -- handler started: close the sample
          lat_v := cnt + 1;
          lb_v  := lat_v - drain;
          pend     <= '0';
          st_count <= st_count + 1;
          st_sum   <= st_sum + lat_v;
          st_last  <= lat_v;
          if (lat_v < st_min) then st_min <= lat_v; end if;
          if (lat_v > st_max) then st_max <= lat_v; end if;
          if (lb_v > st_maxb) then st_maxb <= lb_v; end if;
          if (lat_v > bound) then
            st_nviol <= st_nviol + 1;
            st_viol  <= '1';
          end if;
          h_we  <= '1'; -- increment the bin in the next cycle
          h_bin <= bin_f(lat_v, shift);
          smp_valid_o <= '1';
          smp_lat_o   <= std_ulogic_vector(lat_v);
          smp_drain_o <= std_ulogic_vector(drain);
        else
          cnt <= cnt + 1;
          if (commit = '1') then -- last ordinary commit so far
            drain <= cnt + 1;
          end if;
        end if;
        if (req_i = '1') and (req_q = '0') then -- new edge while still pending
          st_overrun <= st_overrun + 1;
        end if;
      else
        if (req_i = '1') and (req_q = '0') then -- request edge: start a sample
          pend  <= '1';
          cnt   <= (others => '0');
          drain <= (others => '0');
        end if;
        if (resp = '1') then -- trap handler entry with no request outstanding
          st_orphan <= st_orphan + 1;
        end if;
      end if;
    end if;
  end process;

  -- Histogram RAM (distributed): increment or clear, two async read ports ---------------
  hist_ram: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (h_clr = '1') then
        hist(to_integer(h_clr_a)) <= (others => '0');
      elsif (h_we = '1') then
        hist(to_integer(h_bin)) <= hist(to_integer(h_bin)) + 1;
      end if;
    end if;
  end process;
  h_raddr <= unsigned(xbus_req_i.addr(5 downto 2));
  h_rdata <= hist(to_integer(h_raddr));

  viol_o    <= st_viol;
  smp_tag_o <= tag;

  -- Bus interface -----------------------------------------------------------------------
  bus_access: process(rstn_i, clk_i)
    variable a_v : natural range 0 to 31;
  begin
    if (rstn_i = '0') then
      ack   <= '0';
      rdata <= (others => '0');
      bound <= (others => '1');
      shift <= to_unsigned(3, 4);
      tag   <= (others => '0');
      clr   <= '0';
    elsif rising_edge(clk_i) then
      ack   <= xbus_req_i.cyc and xbus_req_i.stb;
      rdata <= (others => '0');
      clr   <= '0';
      a_v   := to_integer(unsigned(xbus_req_i.addr(6 downto 2)));
      if (xbus_req_i.cyc = '1') and (xbus_req_i.stb = '1') then
        if (xbus_req_i.we = '1') then
          case a_v is
            when 0 => clr   <= xbus_req_i.data(0);
                      shift <= unsigned(xbus_req_i.data(11 downto 8));
            when 1 => bound <= unsigned(xbus_req_i.data);
            when 9 => tag   <= xbus_req_i.data;
            when others => null;
          end case;
        else
          case a_v is
            when 0  => rdata(0) <= pend; rdata(1) <= st_viol; rdata(2) <= h_clr; rdata(11 downto 8) <= std_ulogic_vector(shift);
            when 1  => rdata <= std_ulogic_vector(bound);
            when 2  => rdata <= std_ulogic_vector(st_count);
            when 3  => rdata <= std_ulogic_vector(st_min);
            when 4  => rdata <= std_ulogic_vector(st_max);
            when 5  => rdata <= std_ulogic_vector(st_sum);
            when 6  => rdata <= std_ulogic_vector(st_last);
            when 7  => rdata <= std_ulogic_vector(st_nviol);
            when 8  => rdata <= std_ulogic_vector(st_overrun) & std_ulogic_vector(st_orphan);
            when 9  => rdata <= tag;
            when 10 => rdata <= std_ulogic_vector(st_maxb);
            when 16 to 31 => rdata <= std_ulogic_vector(h_rdata);
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;

  xbus_rsp_o.data <= rdata when (ack = '1') else (others => '0');
  xbus_rsp_o.ack  <= ack;
  xbus_rsp_o.err  <= '0';

end architecture;
