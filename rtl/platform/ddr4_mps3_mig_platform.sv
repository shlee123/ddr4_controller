// SPDX-License-Identifier: MIT
// MIG integration contract. This shell deliberately has no DDR pin ports:
// the board-configured MIG integration top exclusively owns physical DDR4
// pins, calibration and PHY timing in BUILD_MODE=mig.

`timescale 1ns/1ps

module ddr4_mps3_mig_platform (
  input  logic sys_clk,
  input  logic sys_rst_n,
  output logic platform_reset_n
);
  // Connect this reset to the board-generated MIG integration top. The MIG
  // itself supplies ui_clk/ui_clk_sync_rst to application-side AXI logic.
  assign platform_reset_n = sys_rst_n;
endmodule : ddr4_mps3_mig_platform
