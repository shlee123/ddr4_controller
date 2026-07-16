# Native-controller DDR clock constraints.
# Clock Wizard output clocks are constrained by its generated XDC. Preserve
# the forwarded DDR clock path through ODDR/OBUFDS and report it explicitly.
set oddr_q [get_pins -quiet -hier -filter {REF_PIN_NAME == Q && NAME =~ *u_ddr_clk_oddr/Q}]
set oddr_c [get_pins -quiet -hier -filter {REF_PIN_NAME == C && NAME =~ *u_ddr_clk_oddr/C}]
if {[llength $oddr_q] == 1 && [llength $oddr_c] == 1} {
  create_generated_clock -name ddr4_ck_forwarded -source $oddr_c -divide_by 1 $oddr_q
}
