# ZCU104 pins for the combined block design (from the board file zcu104/1.1 part0_pins.xml)
# doorbell_button = push button SW0 (GPIO_PB_SW0)
set_property PACKAGE_PIN B4 [get_ports doorbell_button]
set_property IOSTANDARD LVCMOS33 [get_ports doorbell_button]
# too_slow_led = LED 0, doorbell_led = LED 1, awake_led = LED 2, talking_led = LED 3
set_property PACKAGE_PIN D5 [get_ports too_slow_led]
set_property IOSTANDARD LVCMOS33 [get_ports too_slow_led]
set_property PACKAGE_PIN D6 [get_ports doorbell_led]
set_property IOSTANDARD LVCMOS33 [get_ports doorbell_led]
set_property PACKAGE_PIN A5 [get_ports awake_led]
set_property IOSTANDARD LVCMOS33 [get_ports awake_led]
set_property PACKAGE_PIN B5 [get_ports talking_led]
set_property IOSTANDARD LVCMOS33 [get_ports talking_led]
# uart_text_out / uart_text_in = PL UART (uart2_pl: TX C19, RX A20, LVCMOS18)
set_property PACKAGE_PIN C19 [get_ports uart_text_out]
set_property IOSTANDARD LVCMOS18 [get_ports uart_text_out]
set_property PACKAGE_PIN A20 [get_ports uart_text_in]
set_property IOSTANDARD LVCMOS18 [get_ports uart_text_in]
# the button and the UART input are asynchronous to the 100 MHz clock; LEDs and UART out are slow
set_false_path -from [get_ports doorbell_button]
set_false_path -from [get_ports uart_text_in]
set_false_path -to [get_ports {too_slow_led doorbell_led awake_led talking_led uart_text_out}]
