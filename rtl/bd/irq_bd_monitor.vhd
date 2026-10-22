-- irq_bd_monitor ("stopwatch_latency_monitor" in the block design): the verified
-- rtl/irq_lat_mon.vhd, unchanged, with plain std_logic ports. The trace record is
-- rebuilt from valid and intr, the only two fields the monitor reads (lines 112
-- and 113 of irq_lat_mon.vhd); all other fields are tied to zero. The per-sample
-- outputs (testbench log only) are left open.
library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

library work;
use work.irq_bd_pkg.all;

entity irq_bd_monitor is
  port (
    clk         : in  std_logic;
    resetn      : in  std_logic;
    doorbell    : in  std_logic;  -- the same interrupt line the CPU sees
    trace_valid : in  std_logic;
    trace_intr  : in  std_logic;
    bus_request : in  std_logic_vector(76 downto 0);
    bus_reply   : out std_logic_vector(33 downto 0);
    too_slow    : out std_logic   -- sticky: one interrupt took longer than the bound
  );
end entity;

architecture rtl of irq_bd_monitor is
  signal trace : trace_port_t;
  signal req   : xbus_req_t;
  signal rsp   : xbus_rsp_t;
  signal viol  : std_ulogic;
  signal s_valid : std_ulogic;
  signal s_lat, s_drain, s_tag : std_ulogic_vector(31 downto 0);
begin

  trace_fill: process(trace_valid, trace_intr)
    variable t : trace_port_t;
  begin
    t       := trace_port_terminate_c;
    t.valid := trace_valid;
    t.intr  := trace_intr;
    trace   <= t;
  end process;

  req <= req_unpack(bus_request);

  mon_inst: entity neorv32.irq_lat_mon
  port map (
    clk_i       => clk,
    rstn_i      => resetn,
    req_i       => doorbell,
    trace_i     => trace,
    xbus_req_i  => req,
    xbus_rsp_o  => rsp,
    viol_o      => viol,
    smp_valid_o => s_valid,
    smp_lat_o   => s_lat,
    smp_drain_o => s_drain,
    smp_tag_o   => s_tag
  );

  bus_reply <= rsp_pack(rsp);
  too_slow  <= viol;

end architecture;
