// SPDX-License-Identifier: MIT
// DDR4 controller top-level placeholder.
// This module defines the project interface boundary and will be refined incrementally.

module ddr4_controller_top #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 32,
  parameter int APB_ADDR_W = 32,
  parameter int APB_DATA_W = 32
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // AXI4 write address channel
  input  logic [AXI_ADDR_W-1:0]    s_axi_awaddr,
  input  logic [7:0]               s_axi_awlen,
  input  logic [2:0]               s_axi_awsize,
  input  logic [1:0]               s_axi_awburst,
  input  logic                     s_axi_awvalid,
  output logic                     s_axi_awready,

  // AXI4 write data channel
  input  logic [AXI_DATA_W-1:0]    s_axi_wdata,
  input  logic [AXI_DATA_W/8-1:0]  s_axi_wstrb,
  input  logic                     s_axi_wlast,
  input  logic                     s_axi_wvalid,
  output logic                     s_axi_wready,

  // AXI4 write response channel
  output logic [1:0]               s_axi_bresp,
  output logic                     s_axi_bvalid,
  input  logic                     s_axi_bready,

  // AXI4 read address channel
  input  logic [AXI_ADDR_W-1:0]    s_axi_araddr,
  input  logic [7:0]               s_axi_arlen,
  input  logic [2:0]               s_axi_arsize,
  input  logic [1:0]               s_axi_arburst,
  input  logic                     s_axi_arvalid,
  output logic                     s_axi_arready,

  // AXI4 read data channel
  output logic [AXI_DATA_W-1:0]    s_axi_rdata,
  output logic [1:0]               s_axi_rresp,
  output logic                     s_axi_rlast,
  output logic                     s_axi_rvalid,
  input  logic                     s_axi_rready,

  // APB slave interface
  input  logic [APB_ADDR_W-1:0]    paddr,
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [APB_DATA_W-1:0]    pwdata,
  output logic [APB_DATA_W-1:0]    prdata,
  output logic                     pready,
  output logic                     pslverr
);

  // Initial safe placeholder behavior.
  // TODO: replace with AXI/APB/frontend/core implementation.
  assign s_axi_awready = 1'b0;
  assign s_axi_wready  = 1'b0;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_bvalid  = 1'b0;

  assign s_axi_arready = 1'b0;
  assign s_axi_rdata   = '0;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rlast   = 1'b0;
  assign s_axi_rvalid  = 1'b0;

  assign prdata  = '0;
  assign pready  = psel & penable;
  assign pslverr = 1'b0;

endmodule : ddr4_controller_top
