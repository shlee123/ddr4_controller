# TEMPLATE ONLY -- copy to a board-specific XDC and pass it as BOARD_XDC.
# Obtain package pins, I/O bank voltages and standards from the exact MPS3
# platform schematic/board file. Do not uncomment placeholders verbatim.

# set_property PACKAGE_PIN <SYS_CLK_PIN> [get_ports sys_clk]
# set_property IOSTANDARD <SYS_CLK_STANDARD> [get_ports sys_clk]
# set_property PACKAGE_PIN <RESET_PIN> [get_ports sys_rst_n]
# set_property IOSTANDARD <RESET_STANDARD> [get_ports sys_rst_n]

# DDR CK, command/address, control and data pins must be assigned as a complete
# reviewed bank plan. Include DQ/DQS/DM pin locations, differential standards,
# slew/drive properties, termination and any board-specific delays here.
# set_property PACKAGE_PIN <DDR_CK_T_PIN> [get_ports ddr_ck_t]
# set_property PACKAGE_PIN <DDR_CK_C_PIN> [get_ports ddr_ck_c]
# ... DDR4 pin assignments intentionally omitted ...
