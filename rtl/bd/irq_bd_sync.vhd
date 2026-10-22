-- irq_bd_sync ("doorbell_sync" in the block design): two flip-flops that bring
-- the asynchronous push button into the 100 MHz clock domain. Not in the
-- simulated design (there the request is driven on clock edges); the README
-- section 7 notes that a real button needs it and that it adds 2 cycles.
library ieee;
use ieee.std_logic_1164.all;

entity irq_bd_sync is
  port (
    clk      : in  std_logic;
    button   : in  std_logic;
    doorbell : out std_logic
  );
end entity;

architecture rtl of irq_bd_sync is
  signal s1, s2 : std_logic := '0';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of s1 : signal is "TRUE";
  attribute ASYNC_REG of s2 : signal is "TRUE";
begin
  process(clk)
  begin
    if rising_edge(clk) then
      s1 <= button;
      s2 <= s1;
    end if;
  end process;
  doorbell <= s2;
end architecture;
