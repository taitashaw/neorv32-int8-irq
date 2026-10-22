# Batch run of the GUI snapshot sim/gui_dot4 (no GUI): dump the CFU start, the
# instruction word, the operands and the trace pc for the first 1.2 ms (reference pass,
# vectors 0 to 2) to a VCD, to find the times used by the wave views.
set C {/int8irq_wave_top/tb/dut/neorv32_inst/\core_complex_gen(0)\/core_complex_inst/cpu_inst/cpu_alu_inst/cpu_alu_cfu_enabled/cpu_alu_cfu_inst}
open_vcd find_dot4_times.vcd
log_vcd /int8irq_wave_top/tb/clk [get_objects $C/start_i] [get_objects $C/is_dot4] [get_objects $C/is_setacc] [get_objects $C/rs1_i] [get_objects $C/rs2_i] [get_objects $C/valid_o] [get_objects $C/acc] /int8irq_wave_top/tb/p_tr_pc /int8irq_wave_top/tb/p_tr_valid
run 1200us
close_vcd
quit
