# VCD windows around the samples at 23740185, 24676155, 25795805, 35532465, 45294265, 55692915, 65401425, 66234715 ns of sim/run_dot4_final/irq_samples.csv
set C {/int8_irq_tb/dut/neorv32_inst/\core_complex_gen(0)\/core_complex_inst/cpu_inst/cpu_control_inst}
open_vcd dot4_final_events.vcd
log_vcd /int8_irq_tb/clk /int8_irq_tb/irq_mei /int8_irq_tb/smp_valid /int8_irq_tb/smp_lat /int8_irq_tb/smp_drain /int8_irq_tb/smp_tag
log_vcd /int8_irq_tb/p_tr_valid /int8_irq_tb/p_tr_intr /int8_irq_tb/p_tr_pc /int8_irq_tb/p_exec /int8_irq_tb/p_dispatch /int8_irq_tb/p_trap /int8_irq_tb/p_pc_cur /int8_irq_tb/p_fe_valid /int8_irq_tb/p_ic_stb /int8_irq_tb/p_ic_ack /int8_irq_tb/p_cfu_start /int8_irq_tb/p_cfu_done
log_vcd [get_objects $C/env_pend] [get_objects $C/env_enter] [get_objects $C/irq_buf] [get_objects $C/irq_pnd] [get_objects $C/irq_fire]
stop_vcd
run 23739715ns
start_vcd
run 570ns
stop_vcd
run 935150ns
start_vcd
run 820ns
stop_vcd
run 1119130ns
start_vcd
run 520ns
stop_vcd
run 9736080ns
start_vcd
run 580ns
stop_vcd
run 9761210ns
start_vcd
run 590ns
stop_vcd
run 10397630ns
start_vcd
run 1020ns
stop_vcd
run 9707290ns
start_vcd
run 1220ns
stop_vcd
run 832520ns
start_vcd
run 770ns
stop_vcd
close_vcd
