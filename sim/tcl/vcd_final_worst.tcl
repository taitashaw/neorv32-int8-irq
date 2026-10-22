# VCD windows around the samples at 120675, 123485, 7716165, 12770665, 26707605, 37170965, 43358655 ns of sim/run_final/irq_samples.csv
set C {/int8_irq_tb/dut/neorv32_inst/\core_complex_gen(0)\/core_complex_inst/cpu_inst/cpu_control_inst}
open_vcd irq_final_worst.vcd
log_vcd /int8_irq_tb/clk /int8_irq_tb/irq_mei /int8_irq_tb/smp_valid /int8_irq_tb/smp_lat /int8_irq_tb/smp_drain /int8_irq_tb/smp_tag
log_vcd /int8_irq_tb/p_tr_valid /int8_irq_tb/p_tr_intr /int8_irq_tb/p_tr_pc /int8_irq_tb/p_exec /int8_irq_tb/p_dispatch /int8_irq_tb/p_trap /int8_irq_tb/p_pc_cur /int8_irq_tb/p_fe_valid /int8_irq_tb/p_ic_stb /int8_irq_tb/p_ic_ack /int8_irq_tb/p_cfu_start /int8_irq_tb/p_cfu_done
log_vcd [get_objects $C/env_pend] [get_objects $C/env_enter] [get_objects $C/irq_buf] [get_objects $C/irq_pnd] [get_objects $C/irq_fire]
stop_vcd
run 120035ns
start_vcd
run 740ns
stop_vcd
run 2270ns
start_vcd
run 540ns
stop_vcd
run 7591090ns
start_vcd
run 1590ns
stop_vcd
run 5053190ns
start_vcd
run 1310ns
stop_vcd
run 13931900ns
start_vcd
run 5040ns
stop_vcd
run 10462320ns
start_vcd
run 1040ns
stop_vcd
run 6186230ns
start_vcd
run 1460ns
stop_vcd
close_vcd
