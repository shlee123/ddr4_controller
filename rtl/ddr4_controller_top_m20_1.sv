// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_controller_top_m20_1 #(
  parameter int AXI_ADDR_W=32, AXI_DATA_W=32, APB_ADDR_W=32, APB_DATA_W=32,
  parameter int DDR_ADDR_W=17, DDR_BG_W=2, DDR_BA_W=2, DDR_DQ_W=16,
  parameter int DDR_DM_W=DDR_DQ_W/8
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
  inout wire [DDR_DM_W-1:0] ddr_dqs_t, ddr_dqs_c, ddr_dm_n,
  output logic [31:0] perf_cycles, perf_busy_cycles, perf_read_count,
  output logic [31:0] perf_write_count, perf_refresh_count, perf_latency_sum,
  output logic [31:0] perf_max_queue_level,
  output logic burst_error
);
  logic [APB_DATA_W-1:0] core_prdata;
  logic core_pready, core_pslverr;

  ddr4_controller_top #(.AXI_ADDR_W(AXI_ADDR_W),.AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W),.APB_DATA_W(APB_DATA_W),.DDR_ADDR_W(DDR_ADDR_W),
    .DDR_BG_W(DDR_BG_W),.DDR_BA_W(DDR_BA_W),.DDR_DQ_W(DDR_DQ_W),.DDR_DM_W(DDR_DM_W)) u_core (
    .axi_clk,.axi_rst_n,.clk,.rst_n,
    .s_axi_awaddr,.s_axi_awlen,.s_axi_awsize,.s_axi_awburst,.s_axi_awvalid,.s_axi_awready,
    .s_axi_wdata,.s_axi_wstrb,.s_axi_wlast,.s_axi_wvalid,.s_axi_wready,
    .s_axi_bresp,.s_axi_bvalid,.s_axi_bready,
    .s_axi_araddr,.s_axi_arlen,.s_axi_arsize,.s_axi_arburst,.s_axi_arvalid,.s_axi_arready,
    .s_axi_rdata,.s_axi_rresp,.s_axi_rlast,.s_axi_rvalid,.s_axi_rready,
    .paddr,.psel,.penable,.pwrite,.pwdata,.prdata(core_prdata),.pready(core_pready),.pslverr(core_pslverr),
    .ddr_ck_t,.ddr_ck_c,.ddr_reset_n,.ddr_cke,.ddr_cs_n,.ddr_act_n,.ddr_ras_n,.ddr_cas_n,.ddr_we_n,
    .ddr_bg,.ddr_ba,.ddr_a,.ddr_odt,.ddr_par,.ddr_alert_n,.ddr_dq,.ddr_dqs_t,.ddr_dqs_c,.ddr_dm_n);

  logic aw_fire, ar_fire, w_fire, b_fire, r_fire;
  assign aw_fire=s_axi_awvalid&&s_axi_awready;
  assign ar_fire=s_axi_arvalid&&s_axi_arready;
  assign w_fire=s_axi_wvalid&&s_axi_wready;
  assign b_fire=s_axi_bvalid&&s_axi_bready;
  assign r_fire=s_axi_rvalid&&s_axi_rready;

  logic wr_burst_active, rd_burst_active, wr_burst_last, rd_burst_last;
  logic wr_unsup, rd_unsup;
  logic [AXI_ADDR_W-1:0] wr_beat_addr, rd_beat_addr;
  logic [7:0] wr_beat_index, rd_beat_index;
  ddr4_axi_burst_engine #(.ADDR_W(AXI_ADDR_W)) u_wr_burst (
    .clk(axi_clk),.rst_n(axi_rst_n),.start(aw_fire),.start_addr(s_axi_awaddr),
    .burst_len(s_axi_awlen),.burst_size(s_axi_awsize),.burst_type(s_axi_awburst),
    .beat_accept(w_fire),.active(wr_burst_active),.beat_addr(wr_beat_addr),
    .beat_index(wr_beat_index),.beat_last(wr_burst_last),.unsupported(wr_unsup));
  ddr4_axi_burst_engine #(.ADDR_W(AXI_ADDR_W)) u_rd_burst (
    .clk(axi_clk),.rst_n(axi_rst_n),.start(ar_fire),.start_addr(s_axi_araddr),
    .burst_len(s_axi_arlen),.burst_size(s_axi_arsize),.burst_type(s_axi_arburst),
    .beat_accept(r_fire),.active(rd_burst_active),.beat_addr(rd_beat_addr),
    .beat_index(rd_beat_index),.beat_last(rd_burst_last),.unsupported(rd_unsup));
  assign burst_error=wr_unsup|rd_unsup;

  logic [7:0] outstanding;
  always_ff @(posedge axi_clk or negedge axi_rst_n) begin
    if(!axi_rst_n) outstanding<=0;
    else begin
      case ({aw_fire|ar_fire,b_fire|r_fire})
        2'b10: if(outstanding!=8'hff) outstanding<=outstanding+1'b1;
        2'b01: if(outstanding!=0) outstanding<=outstanding-1'b1;
        default: outstanding<=outstanding;
      endcase
    end
  end

  logic cmd_rd,cmd_wr,cmd_ref;
  assign cmd_rd = !ddr_cs_n && ddr_act_n && ddr_ras_n && !ddr_cas_n && ddr_we_n;
  assign cmd_wr = !ddr_cs_n && ddr_act_n && ddr_ras_n && !ddr_cas_n && !ddr_we_n;
  assign cmd_ref= !ddr_cs_n && ddr_act_n && !ddr_ras_n && !ddr_cas_n && ddr_we_n;
  logic [31:0] unused_row_hits;
  ddr4_perf_monitor #(.QUEUE_W(8)) u_perf(
    .clk(axi_clk),.rst_n(axi_rst_n),.req_accept(aw_fire|ar_fire),.rsp_complete(b_fire|r_fire),
    .cmd_rd,.cmd_wr,.cmd_ref,.row_hit(1'b0),.queue_level(outstanding),
    .cycles(perf_cycles),.busy_cycles(perf_busy_cycles),.read_count(perf_read_count),
    .write_count(perf_write_count),.refresh_count(perf_refresh_count),
    .row_hit_count(unused_row_hits),.latency_sum(perf_latency_sum),.max_queue_level(perf_max_queue_level));

  localparam logic [APB_ADDR_W-1:0] PERF_BASE='h100;
  always_comb begin
    prdata=core_prdata; pready=core_pready; pslverr=core_pslverr;
    if(psel&&penable&&!pwrite&&paddr>=PERF_BASE&&paddr<PERF_BASE+'h20) begin
      pready=1'b1; pslverr=1'b0;
      case(paddr-PERF_BASE)
        'h00: prdata=perf_cycles;
        'h04: prdata=perf_busy_cycles;
        'h08: prdata=perf_read_count;
        'h0c: prdata=perf_write_count;
        'h10: prdata=perf_refresh_count;
        'h14: prdata=perf_latency_sum;
        'h18: prdata=perf_max_queue_level;
        'h1c: prdata={{(APB_DATA_W-1){1'b0}},burst_error};
        default: prdata='0;
      endcase
    end
  end
endmodule
