# Timing-only constraints shared by native and MIG integration modes.
# The integration assumes a 100 MHz incoming sys_clk; change this period to
# match the measured board clock before implementation.
create_clock -name sys_clk -period 10.000 [get_ports sys_clk]

# Asynchronous board reset is synchronized independently into generated clock
# domains by ddr4_clock_manager. Do not time recovery from the package pin.
set_false_path -from [get_ports sys_rst_n]
