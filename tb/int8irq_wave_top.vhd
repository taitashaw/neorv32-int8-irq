-- int8irq_wave_top: waveform-view wrapper for the combined design (simulation only).
-- Holds the combined testbench int8_irq_tb (same generics as the verified runs, plus
-- PROBE_EN = true, the setting of the VCD replays) and the viewing helper
-- tb/int8irq_wave_helper.vhd (copied from the INT8 project's int8_wave_helper.vhd with the
-- hierarchy path changed). The helper only reads CFU signals; it adds nothing to the design.
library ieee;
use ieee.std_logic_1164.all;

library neorv32;

entity int8irq_wave_top is
end entity;

architecture sim of int8irq_wave_top is
begin
  tb: entity neorv32.int8_irq_tb
  generic map (
    MEM_LATE  => 16,
    ICACHE_EN => true,
    CFU_EN    => true,
    CSV_FILE  => "irq_samples.csv",
    PROBE_EN  => true
  );
  helper: entity neorv32.int8irq_wave_helper;
end architecture;
