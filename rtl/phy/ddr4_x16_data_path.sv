// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

// Functional DDR x16 datapath for one 32-bit controller word.
// Write: lower halfword is driven on the rising half-cycle and upper halfword
// on the falling half-cycle. Read: both DQS-equivalent clock edges are latched
// and assembled into one 32-bit word.
module ddr4_x16_data_path #(
  parameter integer AXI_DATA_W = 32,
  parameter integer DQ_W = 16,
  parameter integer DM_W = DQ_W/8
)(
  input  wire                  clk,
  input  wire                  rst_n,

  input  wire                  wr_enable,
  input  wire [AXI_DATA_W-1:0] wr_data,
  input  wire [AXI_DATA_W/8-1:0] wr_strb,
  output wire [DQ_W-1:0]       dq_out,
  output wire [DM_W-1:0]       dm_n_out,
  output wire                  dq_oe,
  output wire                  dqs_oe,
  output wire [DM_W-1:0]       dqs_t_out,
  output wire [DM_W-1:0]       dqs_c_out,

  input  wire                  rd_capture_enable,
  input  wire [DQ_W-1:0]       dq_in,
  output reg  [AXI_DATA_W-1:0] rd_data,
  output reg                   rd_data_valid
);
  reg [DQ_W-1:0] rd_rise;
  reg [DQ_W-1:0] rd_fall;
  reg            rd_fall_toggle;
  reg            rd_toggle_sync1;
  reg            rd_toggle_sync2;

  wire phase_high = clk;
  assign dq_out = phase_high ? wr_data[DQ_W-1:0] : wr_data[2*DQ_W-1:DQ_W];
  assign dm_n_out = phase_high ? ~wr_strb[DM_W-1:0] : ~wr_strb[2*DM_W-1:DM_W];
  assign dq_oe = wr_enable;
  assign dqs_oe = wr_enable;
  assign dqs_t_out = {DM_W{clk}};
  assign dqs_c_out = {DM_W{~clk}};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_rise <= {DQ_W{1'b0}};
      rd_toggle_sync1 <= 1'b0;
      rd_toggle_sync2 <= 1'b0;
      rd_data <= {AXI_DATA_W{1'b0}};
      rd_data_valid <= 1'b0;
    end else begin
      rd_data_valid <= 1'b0;
      if (rd_capture_enable)
        rd_rise <= dq_in;
      rd_toggle_sync1 <= rd_fall_toggle;
      rd_toggle_sync2 <= rd_toggle_sync1;
      if (rd_toggle_sync2 != rd_toggle_sync1) begin
        rd_data <= {rd_fall, rd_rise};
        rd_data_valid <= 1'b1;
      end
    end
  end

  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_fall <= {DQ_W{1'b0}};
      rd_fall_toggle <= 1'b0;
    end else if (rd_capture_enable) begin
      rd_fall <= dq_in;
      rd_fall_toggle <= ~rd_fall_toggle;
    end
  end

  initial begin
    if (AXI_DATA_W != 2*DQ_W)
      $error("ddr4_x16_data_path requires AXI_DATA_W == 2*DQ_W");
    if ((AXI_DATA_W/8) != 2*DM_W)
      $error("byte strobe width does not match two x16 transfers");
  end
endmodule
