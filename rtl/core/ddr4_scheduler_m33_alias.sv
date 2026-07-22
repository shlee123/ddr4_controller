// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
import ddr4_ctrl_pkg::*;
module ddr4_scheduler #(
  parameter integer AXI_ADDR_W=32,AXI_DATA_W=32,DDR_ADDR_W=17,
  parameter integer DDR_BG_W=2,DDR_BA_W=2,DDR_DQ_W=16,DDR_DM_W=DDR_DQ_W/8
)(
  input wire clk,input wire rst_n,input wire init_start,output wire init_done,input wire[16:0]mr[0:6],
  input ddr_req_t wr_req_data,input wire wr_req_empty,output wire wr_req_rd,
  input ddr_req_t rd_req_data,input wire rd_req_empty,output wire rd_req_rd,
  output ddr_rsp_t rsp_data,output wire rsp_wr,input wire rsp_full,
  output wire[AXI_ADDR_W-1:0]cache_lookup_addr,input wire cache_hit,input wire[AXI_DATA_W-1:0]cache_lookup_data,
  output wire cache_write_valid,output wire[AXI_ADDR_W-1:0]cache_write_addr,output wire[AXI_DATA_W-1:0]cache_write_data,
  output wire ddr_reset_n,output wire ddr_cke,output wire ddr_cs_n,output wire ddr_act_n,output wire ddr_ras_n,output wire ddr_cas_n,output wire ddr_we_n,
  output wire[DDR_BG_W-1:0]ddr_bg,output wire[DDR_BA_W-1:0]ddr_ba,output wire[DDR_ADDR_W-1:0]ddr_a,output wire ddr_odt,output wire ddr_par,
  input wire[DDR_DQ_W-1:0]ddr_dq_in,output wire[DDR_DQ_W-1:0]ddr_dq_out,output wire ddr_dq_oe,
  output wire[DDR_DM_W-1:0]ddr_dqs_t_out,output wire[DDR_DM_W-1:0]ddr_dqs_c_out,output wire ddr_dqs_oe,
  output wire[DDR_DM_W-1:0]ddr_dm_n_out,output wire ddr_dm_oe
);
  ddr4_scheduler_open_page #(.AXI_ADDR_W(AXI_ADDR_W),.AXI_DATA_W(AXI_DATA_W),.DDR_ADDR_W(DDR_ADDR_W),.DDR_BG_W(DDR_BG_W),.DDR_BA_W(DDR_BA_W),.DDR_DQ_W(DDR_DQ_W),.DDR_DM_W(DDR_DM_W))u_open_page(.*);
endmodule
