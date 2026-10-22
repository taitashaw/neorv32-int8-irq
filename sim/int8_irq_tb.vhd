-- ================================================================================ --
-- int8_irq_tb: testbench for the combined NEORV32 (INT8 CFU + latency monitor)     --
-- Copied from the profiler project's irq_lat_tb. Changes: the DUT is int8_irq_top  --
-- (generics CFU_EN and ICACHE_EN passed through) and two CFU probe signals.        --
-- -------------------------------------------------------------------------------- --
-- * int8_irq_top (NEORV32 with INT8 CFU + irq_lat_mon), 100 MHz clock             --
-- * XBUS device 0: slow memory at 0x40000000 (4 KB, MEM_LATE cycles per access),    --
--   used for loads/stores with wait states and for a handler copy fetched through  --
--   the i-cache                                                                     --
-- * XBUS device 1: interrupt generator at 0xF1000000 that drives irq_mei with       --
--   pseudo-random timing (32-bit LFSR, fixed seed):                                 --
--     0x00 CTRL  W: bit 0 enable      0x04 DMIN  W: minimum delay (cycles)          --
--     0x08 DMASK W: random part mask  0x0C ACK   W: any write drops the line        --
--     0x10 NREQ  R: requests raised   0x14 DONE  W: end of test, value = exit code  --
--   After an ACK (or when enabled) it waits DMIN + (LFSR and DMASK) cycles, then    --
--   raises irq_mei and holds it until the next ACK.                                 --
-- * Every monitor sample goes to a CSV file (tag, latency, drain, time in ns).      --
-- * VHDL assertion gate: a rising monitor violation flag is reported as an error.  --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library neorv32;
use neorv32.neorv32_package.all;

entity int8_irq_tb is
  generic (
    MEM_LATE  : natural := 16;            -- slow memory latency in cycles
    ICACHE_EN : boolean := true;
    CFU_EN    : boolean := true;
    FAST_MUL_EN   : boolean := true;
    FAST_SHIFT_EN : boolean := true;
    DMEM_OUTREG_EN : boolean := false;
    PCLOG_EN  : boolean := false;           -- second CSV with the pc of the instruction each interrupt fired in
    PCLOG_FILE : string := "irq_pc.csv";
    CSV_FILE  : string  := "irq_samples.csv";
    PROBE_EN  : boolean := false            -- copy internal CPU signals to plain TB signals (for VCD)
  );
end entity;

architecture int8_irq_tb_rtl of int8_irq_tb is

  constant t_clk_c : time := 10 ns; -- 100 MHz

  signal clk, rstn : std_ulogic := '0';
  signal irq_mei   : std_ulogic := '0';
  signal uart0_txd : std_ulogic;
  signal viol      : std_ulogic;
  signal smp_valid : std_ulogic;
  signal smp_lat, smp_drain, smp_tag : std_ulogic_vector(31 downto 0);

  signal xbus_req, mem_req, gen_req : xbus_req_t;
  signal xbus_rsp, mem_rsp, gen_rsp : xbus_rsp_t;

  -- generator --
  signal gen_en    : std_ulogic := '0';
  signal gen_dmin  : unsigned(31 downto 0) := (others => '0');
  signal gen_dmask : unsigned(31 downto 0) := (others => '0');
  signal gen_wait  : unsigned(31 downto 0) := (others => '0');
  signal gen_state : natural range 0 to 2 := 0; -- 0 = idle, 1 = counting delay, 2 = line high
  signal gen_nreq  : unsigned(31 downto 0) := (others => '0');
  signal lfsr      : std_ulogic_vector(31 downto 0) := x"1D872B41"; -- fixed seed
  signal done_flag : std_ulogic := '0';
  signal done_code : std_ulogic_vector(31 downto 0) := (others => '0');

  signal cycle     : natural := 0;

  -- probe copies of internal CPU signals (PROBE_EN only) --
  signal p_tr_valid, p_tr_intr, p_exec, p_dispatch, p_trap, p_fe_valid, p_ic_stb, p_ic_ack : std_ulogic := '0';
  signal p_tr_pc, p_pc_cur : std_ulogic_vector(31 downto 0) := (others => '0');
  signal p_cfu_start, p_cfu_done : std_ulogic := '0';

begin

  clk  <= not clk after t_clk_c/2;
  rstn <= '0', '1' after 60 * t_clk_c;

  cycle_count: process(clk)
  begin
    if rising_edge(clk) then
      cycle <= cycle + 1;
    end if;
  end process;

  dut: entity neorv32.int8_irq_top
  generic map (
    CLOCK_FREQUENCY => 100_000_000,
    MON_EN          => true,
    CFU_EN          => CFU_EN,
    FAST_MUL_EN     => FAST_MUL_EN,
    FAST_SHIFT_EN   => FAST_SHIFT_EN,
    DMEM_OUTREG_EN  => DMEM_OUTREG_EN,
    ICACHE_EN       => ICACHE_EN,
    SMP_PORT_EN     => true
  )
  port map (
    clk_i       => clk,
    rstn_i      => rstn,
    uart0_txd_o => uart0_txd,
    uart0_rxd_i => '1',
    irq_mei_i   => irq_mei,
    xbus_adr_o  => xbus_req.addr,
    xbus_dat_o  => xbus_req.data,
    xbus_cti_o  => xbus_req.cti,
    xbus_we_o   => xbus_req.we,
    xbus_sel_o  => xbus_req.sel,
    xbus_stb_o  => xbus_req.stb,
    xbus_cyc_o  => xbus_req.cyc,
    xbus_dat_i  => xbus_rsp.data,
    xbus_ack_i  => xbus_rsp.ack,
    xbus_err_i  => xbus_rsp.err,
    mon_viol_o  => viol,
    smp_valid_o => smp_valid,
    smp_lat_o   => smp_lat,
    smp_drain_o => smp_drain,
    smp_tag_o   => smp_tag
  );
  xbus_req.tag <= (others => '0');

  xbus_interconnect: entity neorv32.xbus_gateway
  generic map (
    DEV_0_EN => true, DEV_0_SIZE => 4096, DEV_0_BASE => x"40000000",
    DEV_1_EN => true, DEV_1_SIZE => 32,   DEV_1_BASE => x"F1000000"
  )
  port map (
    host_req_i  => xbus_req,      host_rsp_o  => xbus_rsp,
    dev_0_req_o => mem_req,       dev_0_rsp_i => mem_rsp,
    dev_1_req_o => gen_req,       dev_1_rsp_i => gen_rsp,
    dev_2_req_o => open,          dev_2_rsp_i => xbus_rsp_terminate_c,
    dev_3_req_o => open,          dev_3_rsp_i => xbus_rsp_terminate_c,
    dev_4_req_o => open,          dev_4_rsp_i => xbus_rsp_terminate_c,
    dev_5_req_o => open,          dev_5_rsp_i => xbus_rsp_terminate_c,
    dev_6_req_o => open,          dev_6_rsp_i => xbus_rsp_terminate_c,
    dev_7_req_o => open,          dev_7_rsp_i => xbus_rsp_terminate_c
  );

  slow_memory: entity neorv32.xbus_memory
  generic map (
    MEM_RST  => false,
    MEM_SIZE => 4096,
    MEM_LATE => MEM_LATE,
    MEM_FILE => ""
  )
  port map (
    clk_i      => clk,
    rstn_i     => rstn,
    xbus_req_i => mem_req,
    xbus_rsp_o => mem_rsp
  );

  -- Interrupt generator -----------------------------------------------------------------
  irq_generator: process(clk)
    variable a_v : natural;
  begin
    if rising_edge(clk) then
      -- free-running Galois LFSR, taps 32,22,2,1 --
      if (lfsr(0) = '1') then
        lfsr <= ('0' & lfsr(31 downto 1)) xor x"80200003";
      else
        lfsr <= '0' & lfsr(31 downto 1);
      end if;

      gen_rsp <= xbus_rsp_terminate_c;
      if (gen_req.cyc = '1') and (gen_req.stb = '1') then
        gen_rsp.ack <= '1';
        a_v := to_integer(unsigned(gen_req.addr(4 downto 2)));
        if (gen_req.we = '1') then
          case a_v is
            when 0 => gen_en    <= gen_req.data(0);
                      if (gen_req.data(0) = '0') then
                        gen_state <= 0;
                        irq_mei   <= '0';
                      end if;
            when 1 => gen_dmin  <= unsigned(gen_req.data);
            when 2 => gen_dmask <= unsigned(gen_req.data);
            when 3 => irq_mei   <= '0'; -- acknowledge
                      if (gen_state = 2) then
                        gen_state <= 0;
                      end if;
            when 5 => done_flag <= '1';
                      done_code <= gen_req.data;
            when others => null;
          end case;
        else
          case a_v is
            when 4      => gen_rsp.data <= std_ulogic_vector(gen_nreq);
            when others => gen_rsp.data <= (others => '0');
          end case;
        end if;
      end if;

      -- request sequencer (a register write above in the same cycle wins) --
      if (gen_en = '1') and not ((gen_req.cyc = '1') and (gen_req.stb = '1') and (gen_req.we = '1')) then
        case gen_state is
          when 0 =>
            gen_wait  <= gen_dmin + (unsigned(lfsr) and gen_dmask);
            gen_state <= 1;
          when 1 =>
            if (gen_wait = 0) then
              irq_mei   <= '1';
              gen_nreq  <= gen_nreq + 1;
              gen_state <= 2;
            else
              gen_wait <= gen_wait - 1;
            end if;
          when others =>
            null; -- line high until ACK
        end case;
      end if;
    end if;
  end process;

  -- Per-sample CSV log ------------------------------------------------------------------
  sample_log: process(clk)
    file     csv_f  : text open write_mode is CSV_FILE;
    variable l      : line;
    variable hdr_v  : boolean := false;
  begin
    if rising_edge(clk) then
      if not hdr_v then
        write(l, string'("tag,latency,drain,entry,time_ns"));
        writeline(csv_f, l);
        hdr_v := true;
      end if;
      if (smp_valid = '1') then
        write(l, to_integer(unsigned(smp_tag)));
        write(l, string'(","));
        write(l, to_integer(unsigned(smp_lat)));
        write(l, string'(","));
        write(l, to_integer(unsigned(smp_drain)));
        write(l, string'(","));
        write(l, to_integer(unsigned(smp_lat)) - to_integer(unsigned(smp_drain)));
        write(l, string'(","));
        write(l, now / 1 ns);
        writeline(csv_f, l);
      end if;
    end if;
  end process;

  -- Hardware gate: VHDL assertion on the monitor's violation flag ------------------------
  gate_assert: process(clk)
    variable viol_q : std_ulogic := '0';
  begin
    if rising_edge(clk) then
      assert not ((viol = '1') and (viol_q = '0'))
        report "[TB:GATE] FAIL: interrupt latency above bound, tag=" & integer'image(to_integer(unsigned(smp_tag))) &
               " latency=" & integer'image(to_integer(unsigned(smp_lat))) & " cycles"
        severity error;
      viol_q := viol;
    end if;
  end process;

  -- Probes: VHDL-2008 external names into the CPU (simulation only) --------------------
  probes:
  if PROBE_EN generate
    alias a_trace is << signal .int8_irq_tb.dut.trace : trace_port_t >>;
    alias a_ctrl  is << signal .int8_irq_tb.dut.neorv32_inst.core_complex_gen(0).core_complex_inst.cpu_inst.ctrl : ctrl_bus_t >>;
    alias a_fe    is << signal .int8_irq_tb.dut.neorv32_inst.core_complex_gen(0).core_complex_inst.cpu_inst.frontend : if_bus_t >>;
    alias a_icreq is << signal .int8_irq_tb.dut.neorv32_inst.core_complex_gen(0).core_complex_inst.icache_req : bus_req_t >>;
    alias a_icrsp is << signal .int8_irq_tb.dut.neorv32_inst.core_complex_gen(0).core_complex_inst.icache_rsp : bus_rsp_t >>;
    alias a_cfudn is << signal .int8_irq_tb.dut.neorv32_inst.core_complex_gen(0).core_complex_inst.cpu_inst.cpu_alu_inst.cfu_done : std_ulogic >>;
  begin
    p_tr_valid <= a_trace.valid;
    p_tr_intr  <= a_trace.intr;
    p_tr_pc    <= a_trace.pc_rdata;
    p_exec     <= a_ctrl.cpu_exec;
    p_dispatch <= a_ctrl.if_ready;
    p_trap     <= a_ctrl.cpu_trap;
    p_pc_cur   <= a_ctrl.pc_cur;
    p_fe_valid <= a_fe.valid;
    p_ic_stb   <= a_icreq.stb;
    p_ic_ack   <= a_icrsp.ack;
    p_cfu_start <= a_ctrl.alu_cp_cfu;
    p_cfu_done  <= a_cfudn;
  end generate;

  -- Second CSV (PCLOG_EN only): for every monitor sample, the pc of the last ordinary
  -- instruction the trace port reported before the handler (the instruction the
  -- interrupt fired in, which always completes) and its commit-to-commit duration.
  pclog:
  if PCLOG_EN generate
    alias a_tr is << signal .int8_irq_tb.dut.trace : trace_port_t >>;
  begin
    pclog_proc: process(clk)
      file     f      : text open write_mode is PCLOG_FILE;
      variable l      : line;
      variable hdr_v  : boolean := false;
      variable last_pc, prev_pc : std_ulogic_vector(31 downto 0) := (others => '0');
      variable last_cyc, prev_cyc : natural := 0;
    begin
      if rising_edge(clk) then
        if not hdr_v then
          write(l, string'("tag,latency,drain,fired_pc,fired_instr_cycles,handler_pc,time_ns"));
          writeline(f, l);
          hdr_v := true;
        end if;
        if (smp_valid = '1') then
          write(l, to_integer(unsigned(smp_tag))); write(l, string'(","));
          write(l, to_integer(unsigned(smp_lat))); write(l, string'(","));
          write(l, to_integer(unsigned(smp_drain))); write(l, string'(",0x"));
          write(l, to_hstring(last_pc)); write(l, string'(","));
          write(l, last_cyc - prev_cyc); write(l, string'(",0x"));
          write(l, to_hstring(a_tr.pc_rdata)); write(l, string'(","));
          write(l, now / 1 ns);
          writeline(f, l);
        end if;
        -- track ordinary commits (the sample of this edge sees the values before it) --
        if (a_tr.valid = '1') and (a_tr.intr = '0') then
          prev_pc := last_pc; prev_cyc := last_cyc;
          last_pc := a_tr.pc_rdata; last_cyc := cycle;
        end if;
      end if;
    end process;
  end generate;

  -- End of test -------------------------------------------------------------------------
  finish_proc: process
  begin
    wait until done_flag = '1';
    wait for 20 * t_clk_c;
    report "[TB] software signalled DONE, code=" & integer'image(to_integer(unsigned(done_code))) &
           " at cycle " & integer'image(cycle) severity note;
    std.env.finish;
    wait;
  end process;

end architecture;
