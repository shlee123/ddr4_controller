# SPDX-License-Identifier: MIT
# Complete Vivado batch flow for the Linux MPS3 integration environment.
# No FPGA part or package pin is guessed here.

proc env_or {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

if {![info exists ::env(XILINX_PART)] || $::env(XILINX_PART) eq ""} {
  error "XILINX_PART is required (example: export XILINX_PART=<exact-device-part>)"
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set mode       [string tolower [env_or BUILD_MODE native]]
set part       $::env(XILINX_PART)
set out_dir    [file normalize [env_or BUILD_DIR [file join $repo_root build vivado $mode]]]
set board_xdc  [env_or BOARD_XDC ""]
set write_bit  [env_or WRITE_BITSTREAM 0]

if {$mode ni {native mig}} { error "BUILD_MODE must be native or mig" }
file mkdir $out_dir
create_project -force ddr4_mps3 [file join $out_dir project] -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

if {$mode eq "native"} {
  set rtl_files [list \
    rtl/pkg/ddr4_ctrl_pkg.sv rtl/sync_fifo.sv rtl/async_fifo.sv \
    rtl/ddr4_data_cache.sv rtl/ddr4_scheduler.sv \
    rtl/phy/ddr4_fpga_clockgen.sv rtl/phy/ddr4_ck_out.sv \
    rtl/phy/ddr4_dq_dqs_phy.sv rtl/ddr4_controller_top.sv \
    rtl/platform/ddr4_clock_manager.sv rtl/platform/ddr4_mps3_native_top.sv]
  set absolute_rtl {}
  foreach f $rtl_files { lappend absolute_rtl [file join $repo_root $f] }
  add_files -norecurse $absolute_rtl
  set_property file_type SystemVerilog [get_files *.sv]
  set_property verilog_define {FPGA NATIVE_DDR4} [current_fileset]

  create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name ddr4_mps3_clk_wiz -dir [file join $out_dir ip]
  set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {500.000} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH}] [get_ips ddr4_mps3_clk_wiz]
  generate_target all [get_ips ddr4_mps3_clk_wiz]
  set top ddr4_mps3_native_top
} else {
  if {![info exists ::env(MIG_XCI)] || ![file exists $::env(MIG_XCI)]} {
    error "MIG mode requires MIG_XCI pointing to a board-configured MIG .xci"
  }
  if {![info exists ::env(MIG_TOP)] || $::env(MIG_TOP) eq ""} {
    error "MIG mode requires MIG_TOP naming the integration top that owns DDR pins"
  }
  add_files -norecurse [file normalize $::env(MIG_XCI)]
  add_files -norecurse [file join $repo_root rtl/platform/ddr4_mps3_mig_platform.sv]
  if {[info exists ::env(MIG_RTL_FILELIST)] && [file exists $::env(MIG_RTL_FILELIST)]} {
    set mig_list_dir [file dirname [file normalize $::env(MIG_RTL_FILELIST)]]
    set fh [open $::env(MIG_RTL_FILELIST) r]
    while {[gets $fh line] >= 0} {
      set line [string trim $line]
      if {$line ne "" && ![string match "#*" $line]} {
        if {[file pathtype $line] eq "relative"} { set line [file join $mig_list_dir $line] }
        add_files -norecurse [file normalize $line]
      }
    }
    close $fh
  }
  set_property verilog_define {FPGA MIG_DDR4} [current_fileset]
  generate_target all [get_files *.xci]
  set top $::env(MIG_TOP)
}

add_files -fileset constrs_1 -norecurse [file join $repo_root constraints/mps3_timing.xdc]
if {$mode eq "native"} {
  add_files -fileset constrs_1 -norecurse [file join $repo_root constraints/ddr4_clocking.xdc]
}
if {$board_xdc ne ""} {
  if {![file exists $board_xdc]} { error "BOARD_XDC does not exist: $board_xdc" }
  add_files -fileset constrs_1 -norecurse [file normalize $board_xdc]
}

set_property top $top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top $top -part $part
write_checkpoint -force [file join $out_dir post_synth.dcp]
report_utilization -file [file join $out_dir post_synth_utilization.rpt]
report_timing_summary -file [file join $out_dir post_synth_timing.rpt]
report_cdc -file [file join $out_dir post_synth_cdc.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out_dir post_route.dcp]
report_route_status -file [file join $out_dir post_route_status.rpt]
report_utilization -file [file join $out_dir post_route_utilization.rpt]
report_timing_summary -max_paths 20 -file [file join $out_dir post_route_timing.rpt]
report_drc -file [file join $out_dir post_route_drc.rpt]

if {$write_bit} {
  if {$board_xdc eq ""} { error "WRITE_BITSTREAM=1 requires BOARD_XDC with reviewed pin/I/O constraints" }
  write_bitstream -force [file join $out_dir ddr4_mps3.bit]
} else {
  puts "INFO: bitstream skipped; set WRITE_BITSTREAM=1 and BOARD_XDC=<reviewed.xdc> to enable it"
}

puts "INFO: Vivado $mode build completed; outputs: $out_dir"
