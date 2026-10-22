# VCD windows of the DOT4 smoke run (sim/run_dot4_smoke, same image):
#  W1 10.0 to 10.8 ms : reference pass, interrupts off (instruction times without interrupts)
#  W2 23.6 to 24.4 ms : DOT4 scenario, inference under interrupts
#  W3 66.99 to 67.49 ms: DOT4BB scenario, back-to-back CFU loop
set C {/int8_irq_tb/dut/neorv32_inst/\core_complex_gen(0)\/core_complex_inst/cpu_inst/cpu_control_inst}
open_vcd dot4_smoke.vcd
log_vcd /int8_irq_tb/clk /int8_irq_tb/irq_mei /int8_irq_tb/smp_valid /int8_irq_tb/smp_lat /int8_irq_tb/smp_drain /int8_irq_tb/smp_tag
log_vcd /int8_irq_tb/p_tr_valid /int8_irq_tb/p_tr_intr /int8_irq_tb/p_tr_pc /int8_irq_tb/p_exec /int8_irq_tb/p_dispatch /int8_irq_tb/p_trap /int8_irq_tb/p_pc_cur /int8_irq_tb/p_fe_valid /int8_irq_tb/p_ic_stb /int8_irq_tb/p_ic_ack /int8_irq_tb/p_cfu_start /int8_irq_tb/p_cfu_done
log_vcd [get_objects $C/env_pend] [get_objects $C/env_enter] [get_objects $C/irq_buf] [get_objects $C/irq_pnd] [get_objects $C/irq_fire]
stop_vcd
run 10000us
start_vcd
run 800us
stop_vcd
run 12800us
start_vcd
run 800us
stop_vcd
run 42590us
start_vcd
run 500us
stop_vcd
close_vcd
