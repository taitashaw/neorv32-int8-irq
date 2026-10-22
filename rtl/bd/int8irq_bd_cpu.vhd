-- int8irq_bd_cpu ("riscv_brain_with_int8_math_helper" in the block design): the NEORV32
-- processor with the INT8 custom instruction, in exactly the configuration of
-- rtl/int8_irq_top.vhd (MON_EN = true, CFU_EN = true, ICACHE_EN = true), with plain
-- std_logic ports so it can be a block-design module reference. The CFU itself is the
-- 2-stage rtl/neorv32_cpu_alu_cfu.vhd, swapped in through the file list by
-- scripts/build_bd.tcl (the NEORV32 sources are unchanged).
-- Trace port: the monitor reads only trace.valid and trace.intr
-- (rtl/irq_lat_mon.vhd), so only those two leave this block.
-- Copied from the profiler project's rtl/bd/irq_bd_cpu.vhd; changes: the generics
-- (CFU, fast multiplier, barrel shifter, 32 KB IMEM) and the entity name.
library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

library work;
use work.irq_bd_pkg.all;

entity int8irq_bd_cpu is
  port (
    clk          : in  std_logic;
    resetn       : in  std_logic;
    irq_doorbell : in  std_logic;  -- machine external interrupt request (irq_mei_i)
    bus_request  : out std_logic_vector(76 downto 0);  -- XBUS request (packed)
    bus_reply    : in  std_logic_vector(33 downto 0);  -- XBUS response (packed)
    trace_valid  : out std_logic;  -- an instruction has completed
    trace_intr   : out std_logic;  -- ... and it is the first instruction of a trap handler
    uart_txd     : out std_logic;
    uart_rxd     : in  std_logic
  );
end entity;

architecture rtl of int8irq_bd_cpu is
  signal trace : trace_port_t;
  signal req   : xbus_req_t;
  signal rsp   : xbus_rsp_t;
  signal txd   : std_ulogic;
begin

  neorv32_inst: entity neorv32.neorv32_top
  generic map (
    CLOCK_FREQUENCY   => 100_000_000,
    TRACE_PORT_EN     => true,
    BOOT_MODE_SELECT  => 2,
    RISCV_ISA_C       => true,
    RISCV_ISA_M       => true,
    RISCV_ISA_Zicntr  => true,
    RISCV_ISA_Xcfu    => true,
    CPU_FAST_MUL_EN   => true,
    CPU_FAST_MUL_REGS => 1,
    CPU_FAST_SHIFT_EN => true,
    IMEM_EN           => true,
    IMEM_SIZE         => 32*1024,
    DMEM_EN           => true,
    DMEM_SIZE         => 8*1024,
    DMEM_OUTREG_EN    => false,
    ICACHE_EN         => true,
    ICACHE_NUM_BLOCKS => 4,
    CACHE_BLOCK_SIZE  => 64,
    XBUS_EN           => true,
    IO_UART0_EN       => true
  )
  port map (
    clk_i        => clk,
    rstn_i       => resetn,
    trace_cpu0_o => trace,
    xbus_adr_o   => req.addr,
    xbus_dat_o   => req.data,
    xbus_cti_o   => req.cti,
    xbus_tag_o   => req.tag,
    xbus_we_o    => req.we,
    xbus_sel_o   => req.sel,
    xbus_stb_o   => req.stb,
    xbus_cyc_o   => req.cyc,
    xbus_dat_i   => rsp.data,
    xbus_ack_i   => rsp.ack,
    xbus_err_i   => rsp.err,
    uart0_txd_o  => txd,
    uart0_rxd_i  => uart_rxd,
    irq_mei_i    => irq_doorbell
  );

  bus_request <= req_pack(req);
  rsp         <= rsp_unpack(bus_reply);
  trace_valid <= trace.valid;
  trace_intr  <= trace.intr;
  uart_txd    <= txd;

end architecture;
