-- ================================================================================ --
-- int8_irq_top: one NEORV32 with the INT8 custom instruction (CFU) and the          --
-- interrupt-latency monitor on the same chip                                       --
-- -------------------------------------------------------------------------------- --
-- Merge of two finished projects:                                                   --
--   * neorv32-int8-cfu   : 2-stage INT8 dot-product CFU (DOT4ACC, SETACC, custom-0) --
--   * neorv32-irq-latency: irq_lat_mon on the XBUS at 0xF00000xx, fed by the CPU    --
--                          trace port and the machine external interrupt line      --
-- One fixed processor configuration, used in simulation and in the out-of-context  --
-- implementation runs:                                                             --
--   rv32imc + Zicsr + Zicntr + Zifencei + Xcfu (INT8 CFU),                          --
--   fast multiplier (DSP, 1 register stage), barrel shifter, serial divider,       --
--   32 KB IMEM (boot from IMEM image), 8 KB DMEM, 4 x 64 B i-cache, no d-cache,     --
--   XBUS, UART0, machine external interrupt (MEI), trace port when MON_EN.         --
-- The CFU source is chosen by the file list (rtl/neorv32_cpu_alu_cfu.vhd for the   --
-- 2-stage version, rtl/neorv32_cpu_alu_cfu_3stage.vhd as the fallback). No NEORV32 --
-- source file is modified.                                                         --
--                                                                                  --
-- MON_EN = false builds the same processor without the trace port and the monitor --
-- and CFU_EN = false builds it without the CFU, so area and timing shares can be   --
-- compared like for like. FAST_MUL_EN = FAST_SHIFT_EN = false gives the profiler  --
-- project's serial multiplier and shifter (used for one controlled check only).    --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity int8_irq_top is
  generic (
    CLOCK_FREQUENCY : natural := 100_000_000;
    MON_EN          : boolean := true;
    CFU_EN          : boolean := true;
    ICACHE_EN       : boolean := true;
    FAST_MUL_EN     : boolean := true;  -- false only for the controlled check against the profiler project
    FAST_SHIFT_EN   : boolean := true;  -- false only for the controlled check against the profiler project
    DMEM_OUTREG_EN  : boolean := false; -- true only for the controlled check against the official testbench
    SMP_PORT_EN     : boolean := false -- per-sample outputs for the testbench log only
  );
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;
    -- UART0 --
    uart0_txd_o : out std_ulogic;
    uart0_rxd_i : in  std_ulogic := '1';
    -- interrupt request (machine external interrupt) --
    irq_mei_i   : in  std_ulogic;
    -- external bus --
    xbus_adr_o  : out std_ulogic_vector(31 downto 0);
    xbus_dat_o  : out std_ulogic_vector(31 downto 0);
    xbus_cti_o  : out std_ulogic_vector(2 downto 0);
    xbus_we_o   : out std_ulogic;
    xbus_sel_o  : out std_ulogic_vector(3 downto 0);
    xbus_stb_o  : out std_ulogic;
    xbus_cyc_o  : out std_ulogic;
    xbus_dat_i  : in  std_ulogic_vector(31 downto 0);
    xbus_ack_i  : in  std_ulogic;
    xbus_err_i  : in  std_ulogic;
    -- monitor status --
    mon_viol_o  : out std_ulogic;
    -- per-sample outputs (only driven when SMP_PORT_EN = true) --
    smp_valid_o : out std_ulogic;
    smp_lat_o   : out std_ulogic_vector(31 downto 0);
    smp_drain_o : out std_ulogic_vector(31 downto 0);
    smp_tag_o   : out std_ulogic_vector(31 downto 0)
  );
end entity;

architecture int8_irq_top_rtl of int8_irq_top is

  signal trace  : trace_port_t;
  signal core_req, mon_req, ext_req : xbus_req_t;
  signal core_rsp, mon_rsp, ext_rsp : xbus_rsp_t;
  signal hit, sel_q : std_ulogic;
  signal s_valid : std_ulogic;
  signal s_lat, s_drain, s_tag : std_ulogic_vector(31 downto 0);

begin

  neorv32_inst: entity neorv32.neorv32_top
  generic map (
    CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
    TRACE_PORT_EN     => MON_EN,
    BOOT_MODE_SELECT  => 2,
    RISCV_ISA_C       => true,
    RISCV_ISA_M       => true,
    RISCV_ISA_Zicntr  => true,
    RISCV_ISA_Xcfu    => CFU_EN,
    CPU_FAST_MUL_EN   => FAST_MUL_EN,
    CPU_FAST_MUL_REGS => 1,
    CPU_FAST_SHIFT_EN => FAST_SHIFT_EN,
    IMEM_EN           => true,
    IMEM_SIZE         => 32*1024,
    DMEM_EN           => true,
    DMEM_SIZE         => 8*1024,
    DMEM_OUTREG_EN    => DMEM_OUTREG_EN,
    ICACHE_EN         => ICACHE_EN,
    ICACHE_NUM_BLOCKS => 4,
    CACHE_BLOCK_SIZE  => 64,
    XBUS_EN           => true,
    IO_UART0_EN       => true
  )
  port map (
    clk_i        => clk_i,
    rstn_i       => rstn_i,
    trace_cpu0_o => trace,
    xbus_adr_o   => core_req.addr,
    xbus_dat_o   => core_req.data,
    xbus_cti_o   => core_req.cti,
    xbus_tag_o   => core_req.tag,
    xbus_we_o    => core_req.we,
    xbus_sel_o   => core_req.sel,
    xbus_stb_o   => core_req.stb,
    xbus_cyc_o   => core_req.cyc,
    xbus_dat_i   => core_rsp.data,
    xbus_ack_i   => core_rsp.ack,
    xbus_err_i   => core_rsp.err,
    uart0_txd_o  => uart0_txd_o,
    uart0_rxd_i  => uart0_rxd_i,
    irq_mei_i    => irq_mei_i
  );

  -- with monitor (same logic as irq_lat_top of the profiler project) --
  mon_enabled:
  if MON_EN generate
    -- address decode: 0xF00000xx is the monitor --
    hit <= '1' when (core_req.addr(31 downto 8) = x"F00000") else '0';

    sel_reg: process(rstn_i, clk_i)
    begin
      if (rstn_i = '0') then
        sel_q <= '0';
      elsif rising_edge(clk_i) then
        if (core_req.stb = '1') then
          sel_q <= hit;
        end if;
      end if;
    end process;

    route: process(core_req, hit, sel_q)
    begin
      mon_req <= core_req;
      ext_req <= core_req;
      if (core_req.stb = '1') then
        mon_req.stb <= hit;
        mon_req.cyc <= core_req.cyc and hit;
        ext_req.stb <= not hit;
        ext_req.cyc <= core_req.cyc and (not hit);
      else
        mon_req.cyc <= core_req.cyc and sel_q;
        ext_req.cyc <= core_req.cyc and (not sel_q);
      end if;
    end process;

    core_rsp <= mon_rsp when (sel_q = '1') else ext_rsp;

    mon_inst: entity work.irq_lat_mon
    port map (
      clk_i       => clk_i,
      rstn_i      => rstn_i,
      req_i       => irq_mei_i,
      trace_i     => trace,
      xbus_req_i  => mon_req,
      xbus_rsp_o  => mon_rsp,
      viol_o      => mon_viol_o,
      smp_valid_o => s_valid,
      smp_lat_o   => s_lat,
      smp_drain_o => s_drain,
      smp_tag_o   => s_tag
    );
  end generate;

  -- without monitor --
  mon_disabled:
  if not MON_EN generate
    ext_req    <= core_req;
    core_rsp   <= ext_rsp;
    mon_viol_o <= '0';
    s_valid    <= '0';
    s_lat      <= (others => '0');
    s_drain    <= (others => '0');
    s_tag      <= (others => '0');
  end generate;

  -- external bus port --
  xbus_adr_o   <= ext_req.addr;
  xbus_dat_o   <= ext_req.data;
  xbus_cti_o   <= ext_req.cti;
  xbus_we_o    <= ext_req.we;
  xbus_sel_o   <= ext_req.sel;
  xbus_stb_o   <= ext_req.stb;
  xbus_cyc_o   <= ext_req.cyc;
  ext_rsp.data <= xbus_dat_i;
  ext_rsp.ack  <= xbus_ack_i;
  ext_rsp.err  <= xbus_err_i;

  -- per-sample outputs --
  smp_valid_o <= s_valid when SMP_PORT_EN else '0';
  smp_lat_o   <= s_lat   when SMP_PORT_EN else (others => '0');
  smp_drain_o <= s_drain when SMP_PORT_EN else (others => '0');
  smp_tag_o   <= s_tag   when SMP_PORT_EN else (others => '0');

end architecture;
