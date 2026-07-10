# Vivado batch synthesis entry point for the Linux MPS3 FPGA environment.
# Usage:
#   XILINX_PART=<vivado-part> vivado -mode batch -source synth/vivado/mps3_synth.tcl

if {![info exists ::env(XILINX_PART)] || $::env(XILINX_PART) eq ""} {
  error "Set XILINX_PART to the Vivado device part for the target MPS3 image."
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set part       $::env(XILINX_PART)

create_project -in_memory -part $part ddr4_controller_mps3

set rtl_files [list \
  [file join $repo_root rtl/pkg/ddr4_ctrl_pkg.sv] \
  [file join $repo_root rtl/sync_fifo.sv] \
  [file join $repo_root rtl/async_fifo.sv] \
  [file join $repo_root rtl/ddr4_data_cache.sv] \
  [file join $repo_root rtl/ddr4_scheduler.sv] \
  [file join $repo_root rtl/phy/ddr4_fpga_clockgen.sv] \
  [file join $repo_root rtl/phy/ddr4_ck_out.sv] \
  [file join $repo_root rtl/phy/ddr4_dq_dqs_phy.sv] \
  [file join $repo_root rtl/ddr4_controller_top.sv] \
]

# FPGA is intentionally the default for this Vivado entry point. It selects
# the ODDR + OBUFDS clock-output implementation in ddr4_ck_out.
read_verilog -sv -define FPGA $rtl_files
synth_design -top ddr4_controller_top -part $part

report_utilization -file [file join $repo_root ddr4_controller_utilization.rpt]
report_timing_summary -file [file join $repo_root ddr4_controller_timing_summary.rpt]
