// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_address_mapper #(
  parameter integer AXI_ADDR_W = 32,
  parameter integer BYTE_OFFSET_W = 2,
  parameter integer COL_W = 10,
  parameter integer BA_W = 2,
  parameter integer BG_W = 2,
  parameter integer ROW_W = 15
)(
  input  wire [AXI_ADDR_W-1:0] axi_addr,
  output wire [COL_W-1:0]      col,
  output wire [BA_W-1:0]       bank,
  output wire [BG_W-1:0]       bank_group,
  output wire [ROW_W-1:0]      row
);
  localparam integer COL_LSB = BYTE_OFFSET_W;
  localparam integer BA_LSB  = COL_LSB + COL_W;
  localparam integer BG_LSB  = BA_LSB + BA_W;
  localparam integer ROW_LSB = BG_LSB + BG_W;
  localparam integer USED_W  = ROW_LSB + ROW_W;

  assign col        = axi_addr[COL_LSB +: COL_W];
  assign bank       = axi_addr[BA_LSB  +: BA_W];
  assign bank_group = axi_addr[BG_LSB  +: BG_W];
  assign row        = axi_addr[ROW_LSB +: ROW_W];

  initial begin
    if (USED_W > AXI_ADDR_W) begin
      $error("DDR address map needs %0d bits, AXI address only has %0d", USED_W, AXI_ADDR_W);
    end
  end
endmodule
