// SPDX-License-Identifier: MIT
// DDR4 controller top-level, Version 2.3.
// AXI/APB front-end plus native DDR request arbitration and timing admission.

`timescale 1ns/1ps

import ddr4_ctrl_pkg::*;

module ddr4_controller_top #(
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
  input logic axi_clk, axi_rst_n, clk, rst_n,
  input logic [AXI_ADDR_W-1:0] s_axi_awaddr,
  input logic [7:0] s_axi_awlen,
  input logic [2:0] s_axi_awsize,
  input logic [1:0] s_axi_awburst,
  input logic s_axi_awvalid,
  output logic s_axi_awready,
  input logic [AXI_DATA_W-1:0] s_axi_wdata,
  input logic [AXI_DATA_W/8-1:0] s_axi_wstrb,
  input logic s_axi_wlast, s_axi_wvalid,
  output logic s_axi_wready,
  output logic [1:0] s_axi_bresp,
  output logic s_axi_bvalid,
  input logic s_axi_bready,
  input logic [AXI_ADDR_W-1:0] s_axi_araddr,
  input logic [7:0] s_axi_arlen,
  input logic [2:0] s_axi_arsize,
  input logic [1:0] s_axi_arburst,
  input logic s_axi_arvalid,
  output logic s_axi_arready,
  output logic [AXI_DATA_W-1:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp,
  output logic s_axi_rlast, s_axi_rvalid,
  input logic s_axi_rready,
  input logic [APB_ADDR_W-1:0] paddr,
  input logic psel, penable, pwrite,
  input logic [APB_DATA_W-1:0] pwdata,
  output logic [APB_DATA_W-1:0] prdata,
  output logic pready, pslverr,
  output logic ddr_ck_t, ddr_ck_c, ddr_reset_n, ddr_cke, ddr_cs_n,
  output logic ddr_act_n, ddr_ras_n, ddr_cas_n, ddr_we_n,
  output logic [DDR_BG_W-1:0] ddr_bg,
  output logic [DDR_BA_W-1:0] ddr_ba,
  output logic [DDR_ADDR_W-1:0] ddr_a,
  output logic ddr_odt, ddr_par,
  input logic ddr_alert_n,
  inout wire [DDR_DQ_W-1:0] ddr_dq,
  inout wire [DDR_DM_W-1:0] ddr_dqs_t, ddr_dqs_c, ddr_dm_n
);
  localparam logic [APB_ADDR_W-1:0] REG_CTRL='h00, REG_STATUS='h04;
  localparam logic [APB_ADDR_W-1:0] REG_MR0='h20, REG_MR1='h24, REG_MR2='h28, REG_MR3='h2c;
  localparam logic [APB_ADDR_W-1:0] REG_MR4='h30, REG_MR5='h34, REG_MR6='h38;
  localparam int AWF_W=AXI_ADDR_W+8+3+2;
  localparam int REQ_W=$bits(ddr_req_t);
  localparam int RSP_W=$bits(ddr_rsp_t);
  typedef struct packed {logic [AXI_ADDR_W-1:0] addr; logic [7:0] len; logic [2:0] size; logic [1:0] burst;} axi_addr_chan_t;

  logic init_done,init_start_axi,init_start_ddr;
  logic [16:0] mr_axi[0:6],mr_ddr[0:6];
  logic cfg_update_tog_axi,cfg_ack_tog_ddr,cfg_ack_sync1_axi,cfg_ack_sync2_axi;
  logic cfg_update_sync1_ddr,cfg_update_sync2_ddr,cfg_update_seen_ddr,cfg_busy_axi;
  logic init_done_sync1_axi,init_done_sync2_axi,apb_wr,apb_rd;
  assign cfg_busy_axi=(cfg_update_tog_axi!=cfg_ack_sync2_axi);
  assign apb_wr=psel&penable&pwrite&!cfg_busy_axi;
  assign apb_rd=psel&penable&~pwrite&!cfg_busy_axi;
  assign pready=psel&penable&!cfg_busy_axi;
  assign pslverr=1'b0;
  integer mi;
  always_ff @(posedge axi_clk or negedge axi_rst_n) begin
    if(!axi_rst_n) begin init_start_axi<=1'b1;cfg_update_tog_axi<=0;cfg_ack_sync1_axi<=0;cfg_ack_sync2_axi<=0;init_done_sync1_axi<=0;init_done_sync2_axi<=0;for(mi=0;mi<7;mi=mi+1)mr_axi[mi]<=mi; end
    else begin cfg_ack_sync1_axi<=cfg_ack_tog_ddr;cfg_ack_sync2_axi<=cfg_ack_sync1_axi;init_done_sync1_axi<=init_done;init_done_sync2_axi<=init_done_sync1_axi;
      if(apb_wr) begin case(paddr)
        REG_CTRL:init_start_axi<=pwdata[0];REG_MR0:mr_axi[0]<=pwdata[16:0];REG_MR1:mr_axi[1]<=pwdata[16:0];REG_MR2:mr_axi[2]<=pwdata[16:0];REG_MR3:mr_axi[3]<=pwdata[16:0];REG_MR4:mr_axi[4]<=pwdata[16:0];REG_MR5:mr_axi[5]<=pwdata[16:0];REG_MR6:mr_axi[6]<=pwdata[16:0];default:;endcase cfg_update_tog_axi<=~cfg_update_tog_axi;end
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin init_start_ddr<=1'b1;cfg_ack_tog_ddr<=0;cfg_update_sync1_ddr<=0;cfg_update_sync2_ddr<=0;cfg_update_seen_ddr<=0;for(mi=0;mi<7;mi=mi+1)mr_ddr[mi]<=mi;end
    else begin cfg_update_sync1_ddr<=cfg_update_tog_axi;cfg_update_sync2_ddr<=cfg_update_sync1_ddr;if(cfg_update_sync2_ddr!=cfg_update_seen_ddr)begin init_start_ddr<=init_start_axi;for(mi=0;mi<7;mi=mi+1)mr_ddr[mi]<=mr_axi[mi];cfg_update_seen_ddr<=cfg_update_sync2_ddr;cfg_ack_tog_ddr<=cfg_update_sync2_ddr;end end
  end
  always_comb begin prdata='0;if(apb_rd)case(paddr)
    REG_CTRL:prdata={{(APB_DATA_W-1){1'b0}},init_start_axi};REG_STATUS:prdata={{(APB_DATA_W-2){1'b0}},ddr_alert_n,init_done_sync2_axi};
    REG_MR0:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[0]};REG_MR1:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[1]};REG_MR2:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[2]};REG_MR3:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[3]};REG_MR4:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[4]};REG_MR5:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[5]};REG_MR6:prdata={{(APB_DATA_W-17){1'b0}},mr_axi[6]};default:prdata='0;endcase end

  axi_addr_chan_t aw_in,aw_out,ar_in,ar_out;
  always_comb begin aw_in.addr=s_axi_awaddr;aw_in.len=s_axi_awlen;aw_in.size=s_axi_awsize;aw_in.burst=s_axi_awburst;ar_in.addr=s_axi_araddr;ar_in.len=s_axi_arlen;ar_in.size=s_axi_arsize;ar_in.burst=s_axi_arburst;end
  logic awf_wr,awf_rd,awf_full,awf_empty,arf_wr,arf_rd,arf_full,arf_empty;
  sync_fifo #(.WIDTH(AWF_W),.DEPTH(AXI_AW_FIFO_DEPTH)) u_aw_fifo(.clk(axi_clk),.rst_n(axi_rst_n),.wr_en(awf_wr),.wr_data(aw_in),.full(awf_full),.rd_en(awf_rd),.rd_data(aw_out),.empty(awf_empty));
  sync_fifo #(.WIDTH(AWF_W),.DEPTH(AXI_AR_FIFO_DEPTH)) u_ar_fifo(.clk(axi_clk),.rst_n(axi_rst_n),.wr_en(arf_wr),.wr_data(ar_in),.full(arf_full),.rd_en(arf_rd),.rd_data(ar_out),.empty(arf_empty));
  assign s_axi_awready=!awf_full;assign awf_wr=s_axi_awvalid&&s_axi_awready;assign s_axi_arready=!arf_full;assign arf_wr=s_axi_arvalid&&s_axi_arready;

  ddr_req_t wr_req_in,rd_req_in,wr_req_fifo,rd_req_fifo,wr_req_native,rd_req_native;
  ddr_rsp_t rsp_in,rsp_out,rsp_hold;
  logic wr_req_wr,rd_req_wr,wr_req_rd,rd_req_rd,wr_fifo_pop,rd_fifo_pop;
  logic wr_req_full,rd_req_full,wr_req_afull,rd_req_afull,wr_req_empty,rd_req_empty;
  logic native_wr_empty,native_rd_empty,native_grant_valid,native_grant_write,native_row_hit,native_timing_violation;
  logic rsp_wr,rsp_rd,rsp_full,rsp_afull,rsp_empty;
  always_comb begin wr_req_in={1'b1,aw_out.addr,s_axi_wdata,s_axi_wstrb,aw_out.len,aw_out.size,aw_out.burst};rd_req_in={1'b0,ar_out.addr,{AXI_DATA_W{1'b0}},{AXI_DATA_W/8{1'b0}},ar_out.len,ar_out.size,ar_out.burst};end
  assign s_axi_wready=!awf_empty&&!wr_req_full;assign wr_req_wr=s_axi_wvalid&&s_axi_wready;assign awf_rd=wr_req_wr;assign rd_req_wr=!arf_empty&&!rd_req_full;assign arf_rd=rd_req_wr;
  async_fifo #(.WIDTH(REQ_W),.DEPTH(REQ_FIFO_DEPTH)) u_wr_req_fifo(.wr_clk(axi_clk),.wr_rst_n(axi_rst_n),.wr_en(wr_req_wr),.wr_data(wr_req_in),.wr_full(wr_req_full),.wr_almost_full(wr_req_afull),.rd_clk(clk),.rd_rst_n(rst_n),.rd_en(wr_fifo_pop),.rd_data(wr_req_fifo),.rd_empty(wr_req_empty));
  async_fifo #(.WIDTH(REQ_W),.DEPTH(REQ_FIFO_DEPTH)) u_rd_req_fifo(.wr_clk(axi_clk),.wr_rst_n(axi_rst_n),.wr_en(rd_req_wr),.wr_data(rd_req_in),.wr_full(rd_req_full),.wr_almost_full(rd_req_afull),.rd_clk(clk),.rd_rst_n(rst_n),.rd_en(rd_fifo_pop),.rd_data(rd_req_fifo),.rd_empty(rd_req_empty));
  ddr4_native_request_mux #(.AXI_ADDR_W(AXI_ADDR_W),.REQ_W(REQ_W)) u_native_request_mux(
    .clk,.rst_n,.wr_req_in(wr_req_fifo),.wr_empty_in(wr_req_empty),.wr_pop(wr_fifo_pop),.wr_req_out(wr_req_native),.wr_empty_out(native_wr_empty),
    .rd_req_in(rd_req_fifo),.rd_empty_in(rd_req_empty),.rd_pop(rd_fifo_pop),.rd_req_out(rd_req_native),.rd_empty_out(native_rd_empty),
    .downstream_wr_pop(wr_req_rd),.downstream_rd_pop(rd_req_rd),.grant_valid(native_grant_valid),.grant_write(native_grant_write),.grant_row_hit(native_row_hit),.timing_violation(native_timing_violation));

  async_fifo #(.WIDTH(RSP_W),.DEPTH(RSP_FIFO_DEPTH)) u_rsp_fifo(.wr_clk(clk),.wr_rst_n(rst_n),.wr_en(rsp_wr),.wr_data(rsp_in),.wr_full(rsp_full),.wr_almost_full(rsp_afull),.rd_clk(axi_clk),.rd_rst_n(axi_rst_n),.rd_en(rsp_rd),.rd_data(rsp_out),.rd_empty(rsp_empty));
  logic rsp_hold_v;
  always_ff @(posedge axi_clk or negedge axi_rst_n) begin if(!axi_rst_n)begin rsp_hold_v<=0;s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_bresp<=0;s_axi_rresp<=0;s_axi_rdata<='0;s_axi_rlast<=0;rsp_hold<='0;end else begin if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;if(!rsp_hold_v&&!rsp_empty)begin rsp_hold<=rsp_out;rsp_hold_v<=1;end else if(rsp_hold_v)begin if(rsp_hold.wr&&!s_axi_bvalid)begin s_axi_bresp<=rsp_hold.resp;s_axi_bvalid<=1;rsp_hold_v<=0;end else if(!rsp_hold.wr&&!s_axi_rvalid)begin s_axi_rdata<=rsp_hold.rdata;s_axi_rresp<=rsp_hold.resp;s_axi_rlast<=rsp_hold.last;s_axi_rvalid<=1;rsp_hold_v<=0;end end end end
  assign rsp_rd=!rsp_hold_v&&!rsp_empty;

  logic [AXI_ADDR_W-1:0] cache_lookup_addr,cache_write_addr;
  logic cache_hit,cache_write_valid,ddr_dq_oe,ddr_dqs_oe,ddr_dm_oe;
  logic [AXI_DATA_W-1:0] cache_lookup_data,cache_write_data;
  logic [DDR_DQ_W-1:0] ddr_dq_in,ddr_dq_out;
  logic [DDR_DM_W-1:0] ddr_dqs_t_out,ddr_dqs_c_out,ddr_dm_n_out;
  assign ddr_dq=ddr_dq_oe?ddr_dq_out:{DDR_DQ_W{1'bz}};assign ddr_dqs_t=ddr_dqs_oe?ddr_dqs_t_out:{DDR_DM_W{1'bz}};assign ddr_dqs_c=ddr_dqs_oe?ddr_dqs_c_out:{DDR_DM_W{1'bz}};assign ddr_dm_n=ddr_dm_oe?ddr_dm_n_out:{DDR_DM_W{1'bz}};assign ddr_dq_in=ddr_dq;
  ddr4_ck_out u_ddr_ck_out(.clk,.ck_t(ddr_ck_t),.ck_c(ddr_ck_c));
  ddr4_data_cache #(.AXI_ADDR_W(AXI_ADDR_W),.AXI_DATA_W(AXI_DATA_W),.CACHE_LINES(CACHE_LINES)) u_data_cache(.clk,.rst_n,.lookup_addr(cache_lookup_addr),.lookup_hit(cache_hit),.lookup_data(cache_lookup_data),.write_valid(cache_write_valid),.write_addr(cache_write_addr),.write_data(cache_write_data),.invalidate(1'b0));
  ddr4_scheduler #(.AXI_ADDR_W(AXI_ADDR_W),.AXI_DATA_W(AXI_DATA_W),.DDR_ADDR_W(DDR_ADDR_W),.DDR_BG_W(DDR_BG_W),.DDR_BA_W(DDR_BA_W),.DDR_DQ_W(DDR_DQ_W),.DDR_DM_W(DDR_DM_W)) u_scheduler(.clk,.rst_n,.init_start(init_start_ddr),.init_done,.mr(mr_ddr),.wr_req_data(wr_req_native),.wr_req_empty(native_wr_empty),.wr_req_rd,.rd_req_data(rd_req_native),.rd_req_empty(native_rd_empty),.rd_req_rd,.rsp_data(rsp_in),.rsp_wr,.rsp_full,.cache_lookup_addr,.cache_hit,.cache_lookup_data,.cache_write_valid,.cache_write_addr,.cache_write_data,.ddr_reset_n,.ddr_cke,.ddr_cs_n,.ddr_act_n,.ddr_ras_n,.ddr_cas_n,.ddr_we_n,.ddr_bg,.ddr_ba,.ddr_a,.ddr_odt,.ddr_par,.ddr_dq_in,.ddr_dq_out,.ddr_dq_oe,.ddr_dqs_t_out,.ddr_dqs_c_out,.ddr_dqs_oe,.ddr_dm_n_out,.ddr_dm_oe);
endmodule : ddr4_controller_top
