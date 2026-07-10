// SPDX-License-Identifier: MIT
// DDR4 controller top-level, Version 2.2.
// AXI/APB front-end plus modular DDR scheduler and 64-line data cache.

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
  input  logic                     axi_clk,
  input  logic                     axi_rst_n,

  input  logic                     clk,
  input  logic                     rst_n,

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

  localparam logic [APB_ADDR_W-1:0] REG_CTRL   = 'h00;
  localparam logic [APB_ADDR_W-1:0] REG_STATUS = 'h04;
  localparam logic [APB_ADDR_W-1:0] REG_MR0    = 'h20;
  localparam logic [APB_ADDR_W-1:0] REG_MR1    = 'h24;
  localparam logic [APB_ADDR_W-1:0] REG_MR2    = 'h28;
  localparam logic [APB_ADDR_W-1:0] REG_MR3    = 'h2c;
  localparam logic [APB_ADDR_W-1:0] REG_MR4    = 'h30;
  localparam logic [APB_ADDR_W-1:0] REG_MR5    = 'h34;
  localparam logic [APB_ADDR_W-1:0] REG_MR6    = 'h38;

  localparam int AWF_W = AXI_ADDR_W + 8 + 3 + 2;
  localparam int REQ_W = $bits(ddr_req_t);
  localparam int RSP_W = $bits(ddr_rsp_t);

  typedef struct packed {
    logic [AXI_ADDR_W-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
  } axi_addr_chan_t;

  logic init_done;
  logic init_start;
  logic [16:0] mr [0:6];

  logic apb_wr, apb_rd;
  assign apb_wr  = psel & penable & pwrite;
  assign apb_rd  = psel & penable & ~pwrite;
  assign pready  = psel & penable;
  assign pslverr = 1'b0;

  always_ff @(posedge axi_clk or negedge axi_rst_n) begin
    if (!axi_rst_n) begin
      init_start <= 1'b1;
      mr[0] <= 17'h0000;
      mr[1] <= 17'h0001;
      mr[2] <= 17'h0002;
      mr[3] <= 17'h0003;
      mr[4] <= 17'h0004;
      mr[5] <= 17'h0005;
      mr[6] <= 17'h0006;
    end else if (apb_wr) begin
      unique case (paddr)
        REG_CTRL: init_start <= pwdata[0];
        REG_MR0:  mr[0] <= pwdata[16:0];
        REG_MR1:  mr[1] <= pwdata[16:0];
        REG_MR2:  mr[2] <= pwdata[16:0];
        REG_MR3:  mr[3] <= pwdata[16:0];
        REG_MR4:  mr[4] <= pwdata[16:0];
        REG_MR5:  mr[5] <= pwdata[16:0];
        REG_MR6:  mr[6] <= pwdata[16:0];
        default: ;
      endcase
    end
  end

  always_comb begin
    prdata = '0;
    if (apb_rd) begin
      unique case (paddr)
        REG_CTRL:   prdata = {{(APB_DATA_W-1){1'b0}}, init_start};
        REG_STATUS: prdata = {{(APB_DATA_W-2){1'b0}}, ddr_alert_n, init_done};
        REG_MR0:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[0]};
        REG_MR1:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[1]};
        REG_MR2:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[2]};
        REG_MR3:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[3]};
        REG_MR4:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[4]};
        REG_MR5:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[5]};
        REG_MR6:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[6]};
        default:    prdata = '0;
      endcase
    end
  end

  axi_addr_chan_t aw_in, aw_out, ar_in, ar_out;
  assign aw_in = '{addr:s_axi_awaddr, len:s_axi_awlen, size:s_axi_awsize, burst:s_axi_awburst};
  assign ar_in = '{addr:s_axi_araddr, len:s_axi_arlen, size:s_axi_arsize, burst:s_axi_arburst};

  logic awf_wr, awf_rd, awf_full, awf_empty;
  logic arf_wr, arf_rd, arf_full, arf_empty;

  sync_fifo #(.WIDTH(AWF_W), .DEPTH(AXI_AW_FIFO_DEPTH)) u_aw_fifo (
    .clk(axi_clk), .rst_n(axi_rst_n), .wr_en(awf_wr), .wr_data(aw_in), .full(awf_full),
    .rd_en(awf_rd), .rd_data(aw_out), .empty(awf_empty));

  sync_fifo #(.WIDTH(AWF_W), .DEPTH(AXI_AR_FIFO_DEPTH)) u_ar_fifo (
    .clk(axi_clk), .rst_n(axi_rst_n), .wr_en(arf_wr), .wr_data(ar_in), .full(arf_full),
    .rd_en(arf_rd), .rd_data(ar_out), .empty(arf_empty));

  assign s_axi_awready = !awf_full;
  assign awf_wr        = s_axi_awvalid && s_axi_awready;
  assign s_axi_arready = !arf_full;
  assign arf_wr        = s_axi_arvalid && s_axi_arready;

  ddr_req_t wr_req_in, rd_req_in, wr_req_out, rd_req_out;
  ddr_rsp_t rsp_in, rsp_out, rsp_hold;
  logic wr_req_wr, rd_req_wr, wr_req_rd, rd_req_rd;
  logic wr_req_full, rd_req_full, wr_req_afull, rd_req_afull;
  logic wr_req_empty, rd_req_empty;
  logic rsp_wr, rsp_rd, rsp_full, rsp_afull, rsp_empty;

  assign wr_req_in = '{wr:1'b1, addr:aw_out.addr, wdata:s_axi_wdata, wstrb:s_axi_wstrb,
                       len:aw_out.len, size:aw_out.size, burst:aw_out.burst};
  assign rd_req_in = '{wr:1'b0, addr:ar_out.addr, wdata:'0, wstrb:'0,
                       len:ar_out.len, size:ar_out.size, burst:ar_out.burst};

  assign s_axi_wready = !awf_empty && !wr_req_full;
  assign wr_req_wr    = s_axi_wvalid && s_axi_wready;
  assign awf_rd       = wr_req_wr;
  assign rd_req_wr    = !arf_empty && !rd_req_full;
  assign arf_rd       = rd_req_wr;

  async_fifo #(.WIDTH(REQ_W), .DEPTH(REQ_FIFO_DEPTH)) u_wr_req_fifo (
    .wr_clk(axi_clk), .wr_rst_n(axi_rst_n), .wr_en(wr_req_wr), .wr_data(wr_req_in), .wr_full(wr_req_full), .wr_almost_full(wr_req_afull),
    .rd_clk(clk), .rd_rst_n(rst_n), .rd_en(wr_req_rd), .rd_data(wr_req_out), .rd_empty(wr_req_empty));

  async_fifo #(.WIDTH(REQ_W), .DEPTH(REQ_FIFO_DEPTH)) u_rd_req_fifo (
    .wr_clk(axi_clk), .wr_rst_n(axi_rst_n), .wr_en(rd_req_wr), .wr_data(rd_req_in), .wr_full(rd_req_full), .wr_almost_full(rd_req_afull),
    .rd_clk(clk), .rd_rst_n(rst_n), .rd_en(rd_req_rd), .rd_data(rd_req_out), .rd_empty(rd_req_empty));

  async_fifo #(.WIDTH(RSP_W), .DEPTH(RSP_FIFO_DEPTH)) u_rsp_fifo (
    .wr_clk(clk), .wr_rst_n(rst_n), .wr_en(rsp_wr), .wr_data(rsp_in), .wr_full(rsp_full), .wr_almost_full(rsp_afull),
    .rd_clk(axi_clk), .rd_rst_n(axi_rst_n), .rd_en(rsp_rd), .rd_data(rsp_out), .rd_empty(rsp_empty));

  logic rsp_hold_v;
  always_ff @(posedge axi_clk or negedge axi_rst_n) begin
    if (!axi_rst_n) begin
      rsp_hold_v   <= 1'b0;
      s_axi_bvalid <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_bresp  <= 2'b00;
      s_axi_rresp  <= 2'b00;
      s_axi_rdata  <= '0;
      s_axi_rlast  <= 1'b0;
    end else begin
      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

      if (!rsp_hold_v && !rsp_empty) begin
        rsp_hold   <= rsp_out;
        rsp_hold_v <= 1'b1;
      end else if (rsp_hold_v) begin
        if (rsp_hold.wr && !s_axi_bvalid) begin
          s_axi_bresp  <= rsp_hold.resp;
          s_axi_bvalid <= 1'b1;
          rsp_hold_v   <= 1'b0;
        end else if (!rsp_hold.wr && !s_axi_rvalid) begin
          s_axi_rdata  <= rsp_hold.rdata;
          s_axi_rresp  <= rsp_hold.resp;
          s_axi_rlast  <= rsp_hold.last;
          s_axi_rvalid <= 1'b1;
          rsp_hold_v   <= 1'b0;
        end
      end
    end
  end
  assign rsp_rd = !rsp_hold_v && !rsp_empty;

  logic [AXI_ADDR_W-1:0] cache_lookup_addr;
  logic                  cache_hit;
  logic [AXI_DATA_W-1:0] cache_lookup_data;
  logic                  cache_write_valid;
  logic [AXI_ADDR_W-1:0] cache_write_addr;
  logic [AXI_DATA_W-1:0] cache_write_data;

  ddr4_data_cache #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .CACHE_LINES(CACHE_LINES)
  ) u_data_cache (
    .clk(clk),
    .rst_n(rst_n),
    .lookup_addr(cache_lookup_addr),
    .lookup_hit(cache_hit),
    .lookup_data(cache_lookup_data),
    .write_valid(cache_write_valid),
    .write_addr(cache_write_addr),
    .write_data(cache_write_data),
    .invalidate(1'b0)
  );

  ddr4_scheduler #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W),
    .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W),
    .DDR_DQ_W(DDR_DQ_W),
    .DDR_DM_W(DDR_DM_W)
  ) u_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .init_start(init_start),
    .init_done(init_done),
    .mr(mr),
    .wr_req_data(wr_req_out),
    .wr_req_empty(wr_req_empty),
    .wr_req_rd(wr_req_rd),
    .rd_req_data(rd_req_out),
    .rd_req_empty(rd_req_empty),
    .rd_req_rd(rd_req_rd),
    .rsp_data(rsp_in),
    .rsp_wr(rsp_wr),
    .rsp_full(rsp_full),
    .cache_lookup_addr(cache_lookup_addr),
    .cache_hit(cache_hit),
    .cache_lookup_data(cache_lookup_data),
    .cache_write_valid(cache_write_valid),
    .cache_write_addr(cache_write_addr),
    .cache_write_data(cache_write_data),
    .ddr_ck_t(ddr_ck_t),
    .ddr_ck_c(ddr_ck_c),
    .ddr_reset_n(ddr_reset_n),
    .ddr_cke(ddr_cke),
    .ddr_cs_n(ddr_cs_n),
    .ddr_act_n(ddr_act_n),
    .ddr_ras_n(ddr_ras_n),
    .ddr_cas_n(ddr_cas_n),
    .ddr_we_n(ddr_we_n),
    .ddr_bg(ddr_bg),
    .ddr_ba(ddr_ba),
    .ddr_a(ddr_a),
    .ddr_odt(ddr_odt),
    .ddr_par(ddr_par),
    .ddr_dq(ddr_dq),
    .ddr_dqs_t(ddr_dqs_t),
    .ddr_dqs_c(ddr_dqs_c),
    .ddr_dm_n(ddr_dm_n)
  );

endmodule : ddr4_controller_top
