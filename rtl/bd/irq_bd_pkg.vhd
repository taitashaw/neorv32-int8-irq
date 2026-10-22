-- irq_bd_pkg: packs the NEORV32 XBUS request/response records into plain
-- std_logic_vectors, so the bus can cross block-design module references
-- (module references cannot have record ports). Bit order, high to low:
--   request (77 bits): addr(32) data(32) cti(3) tag(3) we sel(4) stb cyc
--   reply   (34 bits): data(32) ack err
-- Block-design wrappers only. The verified sources do not use this package.
library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

package irq_bd_pkg is
  constant BUS_REQ_W : natural := 77;
  constant BUS_RSP_W : natural := 34;
  function req_pack   (r : xbus_req_t) return std_logic_vector;
  function req_unpack (v : std_logic_vector(BUS_REQ_W-1 downto 0)) return xbus_req_t;
  function rsp_pack   (r : xbus_rsp_t) return std_logic_vector;
  function rsp_unpack (v : std_logic_vector(BUS_RSP_W-1 downto 0)) return xbus_rsp_t;
end package;

package body irq_bd_pkg is
  function req_pack (r : xbus_req_t) return std_logic_vector is
    variable v : std_logic_vector(BUS_REQ_W-1 downto 0);
  begin
    v(76 downto 45) := std_logic_vector(r.addr);
    v(44 downto 13) := std_logic_vector(r.data);
    v(12 downto 10) := std_logic_vector(r.cti);
    v(9 downto 7)   := std_logic_vector(r.tag);
    v(6)            := r.we;
    v(5 downto 2)   := std_logic_vector(r.sel);
    v(1)            := r.stb;
    v(0)            := r.cyc;
    return v;
  end function;

  function req_unpack (v : std_logic_vector(BUS_REQ_W-1 downto 0)) return xbus_req_t is
    variable r : xbus_req_t;
  begin
    r.addr := std_ulogic_vector(v(76 downto 45));
    r.data := std_ulogic_vector(v(44 downto 13));
    r.cti  := std_ulogic_vector(v(12 downto 10));
    r.tag  := std_ulogic_vector(v(9 downto 7));
    r.we   := v(6);
    r.sel  := std_ulogic_vector(v(5 downto 2));
    r.stb  := v(1);
    r.cyc  := v(0);
    return r;
  end function;

  function rsp_pack (r : xbus_rsp_t) return std_logic_vector is
    variable v : std_logic_vector(BUS_RSP_W-1 downto 0);
  begin
    v(33 downto 2) := std_logic_vector(r.data);
    v(1)           := r.ack;
    v(0)           := r.err;
    return v;
  end function;

  function rsp_unpack (v : std_logic_vector(BUS_RSP_W-1 downto 0)) return xbus_rsp_t is
    variable r : xbus_rsp_t;
  begin
    r.data := std_ulogic_vector(v(33 downto 2));
    r.ack  := v(1);
    r.err  := v(0);
    return r;
  end function;
end package body;
