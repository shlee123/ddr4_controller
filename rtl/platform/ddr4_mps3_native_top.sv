// SPDX-License-Identifier: MIT
// Native/custom-controller platform top. This is the only build mode that
// connects ddr4_controller_top directly to external DDR4 pins.

`timescale 1ns/1ps

module ddr4_mps3_native_top #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 32,
  parameter int APB_ADDR_W = 32,
  parameter int APB_DATA_W = 32,
  parameter int DDR_ADDR_W = 17,
  parameter int DDR_BG_W   = 2,
  parameter int DDR_BA_W   = 2,
  parameter int DDR_DQ_W   = 16,
  parameter int DDR_DM_W   = DDR_DQ_W/8
)(
  input  logic                     sys_clk,
  input  logic                     sys_rst_n,
  output logic                     clock_locked,

  input  logic [AXI_ADDR_W-1:0]    s_axi_awaddr,
  input  logic [7:0]               s_axi_awlen,
  input  logic [2:0]               s_axi_awsize,
  input  logic [1:0]               s_axi_awburst,
  input  logic                     s_axi_awvalid,
  output logic                     s_axi_awready,
  input  logic [AXI_DATA_W-1:0]    s_axi_wdata,
  input  logic [AXI_DATA_W/8-1:0]  s_axi_wstrb,
  input  logic                     s_axi_wlast,
  input  logic                     s_axi_wvalid,
  output logic                     s_axi_wready,
  output logic [1:0]               s_axi_bresp,
  output logic                     s_axi_bvalid,
  input  logic                     s_axi_bready,
  input  logic [AXI_ADDR_W-1:0]    s_axi_araddr,
  input  logic [7:0]               s_axi_arlen,
  input  logic [2:0]               s_axi_arsize,
  input  logic [1:0]               s_axi_arburst,
  input  logic                     s_axi_arvalid,
  output logic                     s_axi_arready,
  output logic [AXI_DATA_W-1:0]    s_axi_rdata,
  output logic [1:0]               s_axi_rresp,
  output logic                     s_axi_rlast,
  output logic                     s_axi_rvalid,
  input  logic                     s_axi_rready,

  input  logic [APB_ADDR_W-1:0]    paddr,
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [APB_DATA_W-1:0]    pwdata,
  output logic [APB_DATA_W-1:0]    prdata,
  output logic                     pready,
  output logic                     pslverr,

  output logic                     ddr_ck_t,
  output logic                     ddr_ck_c,
  output logic                     ddr_reset_n,
  output logic                     ddr_cke,
  output logic                     ddr_cs_n,
  output logic                     ddr_act_n,
  output logic                     ddr_ras_n,
  output logic                     ddr_cas_n,
  output logic                     ddr_we_n,
  output logic [DDR_BG_W-1:0]      ddr_bg,
  output logic [DDR_BA_W-1:0]      ddr_ba,
  output logic [DDR_ADDR_W-1:0]    ddr_a,
  output logic                     ddr_odt,
  output logic                     ddr_par,
  input  logic                     ddr_alert_n,
  inout  wire [DDR_DQ_W-1:0]       ddr_dq,
  inout  wire [DDR_DM_W-1:0]       ddr_dqs_t,
  inout  wire [DDR_DM_W-1:0]       ddr_dqs_c,
  inout  wire [DDR_DM_W-1:0]       ddr_dm_n
);

  logic axi_clk_i, axi_rst_n_i, ddr_clk_i, ddr_rst_n_i;

  ddr4_clock_manager u_clock_manager (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
    .axi_clk(axi_clk_i), .axi_rst_n(axi_rst_n_i),
    .ddr_clk(ddr_clk_i), .ddr_rst_n(ddr_rst_n_i),
    .locked(clock_locked)
  );

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W), .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W), .APB_DATA_W(APB_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W), .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W), .DDR_DQ_W(DDR_DQ_W), .DDR_DM_W(DDR_DM_W)
  ) u_controller (
    .axi_clk(axi_clk_i), .axi_rst_n(axi_rst_n_i),
    .clk(ddr_clk_i), .rst_n(ddr_rst_n_i),
    .*
  );

endmodule : ddr4_mps3_native_top
