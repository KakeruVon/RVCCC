create_clock -period 40.000 -name clk -waveform {0.000 20.000} [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports {ledr[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ledr[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ledr[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ledr[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports sysrst]
set_property PACKAGE_PIN U18 [get_ports clk]
set_property PACKAGE_PIN N15 [get_ports sysrst]
set_property PACKAGE_PIN M15 [get_ports {ledr[2]}]
set_property PACKAGE_PIN M14 [get_ports {ledr[3]}]
set_property PACKAGE_PIN K16 [get_ports {ledr[1]}]
set_property PACKAGE_PIN J16 [get_ports {ledr[0]}]




set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN H15 [get_ports uart_tx]
set_property PACKAGE_PIN K14 [get_ports uart_rx]

set_property SLEW FAST [get_ports uart_tx]
