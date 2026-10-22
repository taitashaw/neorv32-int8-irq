-- irq_bd_bus_switch ("address_switch" in the block design): the XBUS address
-- decode of rtl/irq_lat_top.vhd (mon_enabled generate: sel_reg, route, core_rsp),
-- copied unchanged into its own block. Addresses 0xF00000xx go to the latency
-- monitor; every other address goes to the "other" port.
library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

library work;
use work.irq_bd_pkg.all;

entity irq_bd_bus_switch is
  port (
    clk             : in  std_logic;
    resetn          : in  std_logic;
    cpu_request     : in  std_logic_vector(76 downto 0);
    cpu_reply       : out std_logic_vector(33 downto 0);
    monitor_request : out std_logic_vector(76 downto 0);
    monitor_reply   : in  std_logic_vector(33 downto 0);
    other_request   : out std_logic_vector(76 downto 0);
    other_reply     : in  std_logic_vector(33 downto 0)
  );
end entity;

architecture rtl of irq_bd_bus_switch is
  signal core_req, mon_req, ext_req : xbus_req_t;
  signal core_rsp, mon_rsp, ext_rsp : xbus_rsp_t;
  signal hit, sel_q : std_ulogic;
begin

  core_req <= req_unpack(cpu_request);
  mon_rsp  <= rsp_unpack(monitor_reply);
  ext_rsp  <= rsp_unpack(other_reply);

  -- address decode: 0xF00000xx is the monitor --
  hit <= '1' when (core_req.addr(31 downto 8) = x"F00000") else '0';

  sel_reg: process(resetn, clk)
  begin
    if (resetn = '0') then
      sel_q <= '0';
    elsif rising_edge(clk) then
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

  cpu_reply       <= rsp_pack(core_rsp);
  monitor_request <= req_pack(mon_req);
  other_request   <= req_pack(ext_req);

end architecture;
