// SPDX-License-Identifier: MIT
// Platform clock/reset wrapper. Vivado creates ddr4_mps3_clk_wiz in FPGA
// builds; the portable branch exists only for RTL simulation/lint.

`timescale 1ns/1ps

module ddr4_clock_manager (
  input  logic sys_clk,
  input  logic sys_rst_n,
  output logic axi_clk,
  output logic axi_rst_n,
  output logic ddr_clk,
  output logic ddr_rst_n,
  output logic locked
);

`ifdef FPGA
  wire axi_clk_i, ddr_clk_i, locked_i;
  logic [1:0] axi_reset_sync, ddr_reset_sync;

  ddr4_mps3_clk_wiz u_clk_wiz (
    .clk_in1  (sys_clk),
    .reset    (~sys_rst_n),
    .clk_out1 (axi_clk_i),
    .clk_out2 (ddr_clk_i),
    .locked   (locked_i)
  );

  assign axi_clk = axi_clk_i;
  assign ddr_clk = ddr_clk_i;
  assign locked  = locked_i;

  always_ff @(posedge axi_clk_i or negedge sys_rst_n) begin
    if (!sys_rst_n) axi_reset_sync <= 2'b00;
    else            axi_reset_sync <= {axi_reset_sync[0], locked_i};
  end
  always_ff @(posedge ddr_clk_i or negedge sys_rst_n) begin
    if (!sys_rst_n) ddr_reset_sync <= 2'b00;
    else            ddr_reset_sync <= {ddr_reset_sync[0], locked_i};
  end
  assign axi_rst_n = axi_reset_sync[1];
  assign ddr_rst_n = ddr_reset_sync[1];
`else
  // Structural simulation fallback: testbenches that need true asynchronous
  // 200/500 MHz clocks should instantiate ddr4_controller_top directly.
  assign axi_clk   = sys_clk;
  assign ddr_clk   = sys_clk;
  assign locked    = sys_rst_n;
  assign axi_rst_n = sys_rst_n;
  assign ddr_rst_n = sys_rst_n;
`endif

endmodule : ddr4_clock_manager
