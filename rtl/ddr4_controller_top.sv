// SPDX-License-Identifier: MIT
// DDR4 controller top-level, Version 2.1.
// Integrated async AXI/APB-to-DDR scheduler, read-priority policy, AW/AR FIFOs,
// async request/response FIFOs, and 64-line direct-mapped cache.

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
  // AXI/APB clock domain, target 200 MHz.
  input  logic                     axi_clk,
  input  logic                     axi_rst_n,

  // DDR controller/PHY command clock domain, target 500 MHz.
  // The original V2 port names are preserved and now represent the DDR domain.
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

  localparam int AWF_W       = AXI_ADDR_W + 8 + 3 + 2;
  localparam int REQ_W       = $bits(ddr_req_t);
  localparam int RSP_W       = $bits(ddr_rsp_t);
  localparam int CACHE_IDX_W = $clog2(CACHE_LINES);

  typedef enum logic [4:0] {
    INIT_RESET,
    INIT_WAIT_CKE,
    INIT_MR3,
    INIT_MR6,
    INIT_MR5,
    INIT_MR4,
    INIT_MR2,
    INIT_MR1,
    INIT_MR0,
    INIT_ZQCL,
    INIT_ZQWAIT,
    INIT_READY,
    APP_IDLE,
    APP_ACT,
    APP_TRCD,
    APP_WR,
    APP_RD,
    APP_RLAT,
    APP_PRE,
    APP_TRP,
    APP_RESP
  } ctrl_state_e;

  typedef struct packed {
    logic [AXI_ADDR_W-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
  } axi_addr_chan_t;

  ctrl_state_e state;
  logic [15:0] wait_cnt;
  logic        init_done;
  logic        init_start;
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

  // AXI AW/AR front-end FIFOs: eight entries each.
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

  // 64-entry direct-mapped cache in the DDR clock domain.
  ddr_req_t cur_req;
  logic [AXI_DATA_W-1:0] cache_data [0:CACHE_LINES-1];
  logic [AXI_ADDR_W-1:CACHE_IDX_W+2] cache_tag [0:CACHE_LINES-1];
  logic cache_valid [0:CACHE_LINES-1];
  logic [CACHE_IDX_W-1:0] cur_idx;
  logic cache_hit;
  assign cur_idx   = cur_req.addr[CACHE_IDX_W+1:2];
  assign cache_hit = cache_valid[cur_idx] && (cache_tag[cur_idx] == cur_req.addr[AXI_ADDR_W-1:CACHE_IDX_W+2]);

  logic [DDR_DQ_W-1:0] dq_out;
  logic dq_oe;
  assign ddr_ck_t  = clk;
  assign ddr_ck_c  = ~clk;
  assign ddr_dq    = dq_oe ? dq_out : 'z;
  assign ddr_dqs_t = dq_oe ? {DDR_DM_W{clk}} : 'z;
  assign ddr_dqs_c = dq_oe ? {DDR_DM_W{~clk}} : 'z;
  assign ddr_dm_n  = dq_oe ? ~cur_req.wstrb[DDR_DM_W-1:0] : 'z;

  function automatic logic [AXI_ADDR_W-1:0] axi_next_addr(
    input logic [AXI_ADDR_W-1:0] base,
    input logic [AXI_ADDR_W-1:0] cur,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    logic [AXI_ADDR_W-1:0] beat_bytes;
    logic [AXI_ADDR_W-1:0] wrap_bytes;
    logic [AXI_ADDR_W-1:0] wrap_mask;
    logic [AXI_ADDR_W-1:0] next_linear;
    begin
      beat_bytes  = {{(AXI_ADDR_W-1){1'b0}}, 1'b1} << size;
      wrap_bytes  = beat_bytes * ({{(AXI_ADDR_W-8){1'b0}}, len} + {{(AXI_ADDR_W-1){1'b0}}, 1'b1});
      wrap_mask   = wrap_bytes - {{(AXI_ADDR_W-1){1'b0}}, 1'b1};
      next_linear = cur + beat_bytes;
      unique case (burst)
        2'b00: axi_next_addr = cur;
        2'b01: axi_next_addr = next_linear;
        2'b10: axi_next_addr = (base & ~wrap_mask) | (next_linear & wrap_mask);
        default: axi_next_addr = next_linear;
      endcase
    end
  endfunction

  function automatic [DDR_BG_W-1:0] addr_bg(input logic [AXI_ADDR_W-1:0] a); return a[25 +: DDR_BG_W]; endfunction
  function automatic [DDR_BA_W-1:0] addr_ba(input logic [AXI_ADDR_W-1:0] a); return a[23 +: DDR_BA_W]; endfunction
  function automatic [DDR_ROW_W-1:0] addr_row(input logic [AXI_ADDR_W-1:0] a); return a[22:8]; endfunction
  function automatic [DDR_COL_W-1:0] addr_col(input logic [AXI_ADDR_W-1:0] a); return a[11:2]; endfunction

  task automatic drive_des;
    begin
      ddr_cs_n  <= 1'b1;
      ddr_act_n <= 1'b1;
      ddr_ras_n <= 1'b1;
      ddr_cas_n <= 1'b1;
      ddr_we_n  <= 1'b1;
    end
  endtask

  always_comb begin
    wr_req_rd = 1'b0;
    rd_req_rd = 1'b0;
    rsp_wr    = 1'b0;
    if (state == APP_IDLE && init_done && !rsp_full) begin
      // Scheduler policy: read cycle priority over write cycle.
      if (!rd_req_empty) rd_req_rd = 1'b1;
      else if (!wr_req_empty) wr_req_rd = 1'b1;
    end
    if (state == APP_RESP && !rsp_full) rsp_wr = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= INIT_RESET;
      wait_cnt    <= '0;
      init_done   <= 1'b0;
      ddr_reset_n <= 1'b0;
      ddr_cke     <= 1'b0;
      ddr_odt     <= 1'b0;
      ddr_par     <= 1'b0;
      ddr_cs_n    <= 1'b1;
      ddr_act_n   <= 1'b1;
      ddr_ras_n   <= 1'b1;
      ddr_cas_n   <= 1'b1;
      ddr_we_n    <= 1'b1;
      ddr_bg      <= '0;
      ddr_ba      <= '0;
      ddr_a       <= '0;
      dq_out      <= '0;
      dq_oe       <= 1'b0;
      cur_req     <= '0;
      rsp_in      <= '0;
      for (int i=0; i<CACHE_LINES; i++) begin
        cache_valid[i] <= 1'b0;
        cache_data[i]  <= '0;
        cache_tag[i]   <= '0;
      end
    end else begin
      drive_des();
      ddr_reset_n <= 1'b1;
      ddr_cke     <= 1'b1;
      ddr_odt     <= 1'b1;
      ddr_par     <= 1'b0;
      dq_oe       <= 1'b0;
      if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;

      unique case (state)
        INIT_RESET: begin
          ddr_reset_n <= 1'b1;
          ddr_cke     <= 1'b0;
          if (init_start) begin
            wait_cnt <= 16'd32;
            state    <= INIT_WAIT_CKE;
          end
        end
        INIT_WAIT_CKE: begin
          ddr_cke <= 1'b1;
          if (wait_cnt == 0) state <= INIT_MR3;
        end
        INIT_MR3: begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd3; ddr_bg <= '0; ddr_a <= mr[3]; wait_cnt <= T_MRD_CK; state <= INIT_MR6;
        end
        INIT_MR6: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd2; ddr_bg <= {{(DDR_BG_W-1){1'b0}},1'b1}; ddr_a <= mr[6]; wait_cnt <= T_MRD_CK; state <= INIT_MR5;
        end
        INIT_MR5: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd1; ddr_bg <= {{(DDR_BG_W-1){1'b0}},1'b1}; ddr_a <= mr[5]; wait_cnt <= T_MRD_CK; state <= INIT_MR4;
        end
        INIT_MR4: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd0; ddr_bg <= {{(DDR_BG_W-1){1'b0}},1'b1}; ddr_a <= mr[4]; wait_cnt <= T_MRD_CK; state <= INIT_MR2;
        end
        INIT_MR2: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd2; ddr_bg <= '0; ddr_a <= mr[2]; wait_cnt <= T_MRD_CK; state <= INIT_MR1;
        end
        INIT_MR1: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd1; ddr_bg <= '0; ddr_a <= mr[1]; wait_cnt <= T_MRD_CK; state <= INIT_MR0;
        end
        INIT_MR0: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= 2'd0; ddr_bg <= '0; ddr_a <= mr[0]; wait_cnt <= T_MOD_CK; state <= INIT_ZQCL;
        end
        INIT_ZQCL: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b1; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b0;
          ddr_a <= 17'h00400; wait_cnt <= T_ZQINIT_CK[15:0]; state <= INIT_ZQWAIT;
        end
        INIT_ZQWAIT: if (wait_cnt == 0) state <= INIT_READY;
        INIT_READY: begin init_done <= 1'b1; state <= APP_IDLE; end

        APP_IDLE: begin
          if (!rsp_full) begin
            if (!rd_req_empty) begin
              cur_req <= rd_req_out;
              state   <= APP_ACT;
            end else if (!wr_req_empty) begin
              cur_req <= wr_req_out;
              state   <= APP_ACT;
            end
          end
        end
        APP_ACT: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b0;
          ddr_ras_n <= addr_row(cur_req.addr)[14];
          ddr_cas_n <= addr_row(cur_req.addr)[13];
          ddr_we_n  <= addr_row(cur_req.addr)[12];
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= {{(DDR_ADDR_W-DDR_ROW_W){1'b0}}, addr_row(cur_req.addr)};
          wait_cnt  <= T_RCD_CK;
          state     <= APP_TRCD;
        end
        APP_TRCD: if (wait_cnt == 0) begin
          if (cur_req.wr) state <= APP_WR;
          else if (cache_hit) state <= APP_RESP;
          else state <= APP_RD;
        end
        APP_WR: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b1;
          ddr_cas_n <= 1'b0;
          ddr_we_n  <= 1'b0;
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= {{(DDR_ADDR_W-DDR_COL_W){1'b0}}, addr_col(cur_req.addr)};
          dq_out    <= cur_req.wdata[DDR_DQ_W-1:0];
          dq_oe     <= 1'b1;
          cache_data[cur_idx]  <= cur_req.wdata;
          cache_tag[cur_idx]   <= cur_req.addr[AXI_ADDR_W-1:CACHE_IDX_W+2];
          cache_valid[cur_idx] <= 1'b1;
          wait_cnt <= T_CWL_CK;
          state    <= APP_PRE;
        end
        APP_RD: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b1;
          ddr_cas_n <= 1'b0;
          ddr_we_n  <= 1'b1;
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= {{(DDR_ADDR_W-DDR_COL_W){1'b0}}, addr_col(cur_req.addr)};
          wait_cnt  <= T_CL_CK;
          state     <= APP_RLAT;
        end
        APP_RLAT: if (wait_cnt == 0) begin
          cache_data[cur_idx]  <= {{(AXI_DATA_W-DDR_DQ_W){1'b0}}, ddr_dq};
          cache_tag[cur_idx]   <= cur_req.addr[AXI_ADDR_W-1:CACHE_IDX_W+2];
          cache_valid[cur_idx] <= 1'b1;
          state <= APP_PRE;
        end
        APP_PRE: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b0;
          ddr_cas_n <= 1'b1;
          ddr_we_n  <= 1'b0;
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= '0;
          ddr_a[10] <= 1'b1;
          wait_cnt <= T_RP_CK;
          state    <= APP_TRP;
        end
        APP_TRP: if (wait_cnt == 0) state <= APP_RESP;
        APP_RESP: if (!rsp_full) begin
          if (cur_req.wr) begin
            rsp_in <= '{wr:1'b1, addr:cur_req.addr, rdata:'0, resp:2'b00, last:1'b1};
          end else begin
            rsp_in <= '{wr:1'b0, addr:cur_req.addr, rdata:cache_data[cur_idx], resp:2'b00, last:1'b1};
          end
          state <= APP_IDLE;
        end
        default: state <= INIT_RESET;
      endcase
    end
  end

endmodule : ddr4_controller_top
