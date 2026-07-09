`timescale 1ns/1ps
module ddr4_ctrl_top
  import ddr4_pkg::*;
#(
  parameter int AXI_ADDR_W_P = AXI_ADDR_W,
  parameter int AXI_DATA_W_P = AXI_DATA_W
)(
  input  logic aclk,
  input  logic aresetn,
  input  logic ddr_clk,
  input  logic ddr_resetn,

  input  logic [AXI_ADDR_W_P-1:0] s_axi_awaddr,
  input  logic [7:0]              s_axi_awlen,
  input  logic [1:0]              s_axi_awburst,
  input  logic                    s_axi_awvalid,
  output logic                    s_axi_awready,
  input  logic [AXI_DATA_W_P-1:0] s_axi_wdata,
  input  logic [AXI_DATA_W_P/8-1:0] s_axi_wstrb,
  input  logic                    s_axi_wlast,
  input  logic                    s_axi_wvalid,
  output logic                    s_axi_wready,
  output logic [1:0]              s_axi_bresp,
  output logic                    s_axi_bvalid,
  input  logic                    s_axi_bready,

  input  logic [AXI_ADDR_W_P-1:0] s_axi_araddr,
  input  logic [7:0]              s_axi_arlen,
  input  logic [1:0]              s_axi_arburst,
  input  logic                    s_axi_arvalid,
  output logic                    s_axi_arready,
  output logic [AXI_DATA_W_P-1:0] s_axi_rdata,
  output logic [1:0]              s_axi_rresp,
  output logic                    s_axi_rlast,
  output logic                    s_axi_rvalid,
  input  logic                    s_axi_rready,

  input  logic                    psel,
  input  logic                    penable,
  input  logic                    pwrite,
  input  logic [31:0]             paddr,
  input  logic [31:0]             pwdata,
  output logic [31:0]             prdata,
  output logic                    pready,
  output logic                    pslverr,

  output logic                    ddr4_reset_n,
  output logic                    ddr4_ck_t,
  output logic                    ddr4_ck_c,
  output logic                    ddr4_cke,
  output logic                    ddr4_cs_n,
  output logic                    ddr4_act_n,
  output logic                    ddr4_ras_n,
  output logic                    ddr4_cas_n,
  output logic                    ddr4_we_n,
  output logic [DDR4_ADDR_W-1:0]  ddr4_a,
  output logic [DDR4_BA_W-1:0]    ddr4_ba,
  output logic [DDR4_BG_W-1:0]    ddr4_bg,
  output logic                    ddr4_odt,
  inout  wire  [DDR4_DQ_W-1:0]    ddr4_dq,
  inout  wire  [DDR4_DQS_W-1:0]   ddr4_dqs_t,
  inout  wire  [DDR4_DQS_W-1:0]   ddr4_dqs_c,
  output logic [DDR4_DQS_W-1:0]   ddr4_dm_n,
  input  logic                    ddr4_alert_n
);
  localparam int AWF_W  = AXI_ADDR_W_P;
  localparam int REQ_W  = $bits(req_t);
  localparam int RSP_W  = $bits(rsp_t);
  localparam int CACHE_IDX_W = $clog2(CACHE_LINES);

  logic [31:0] cfg_mr[0:7];
  assign pready  = 1'b1;
  assign pslverr = 1'b0;
  always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      for(int i=0;i<8;i++) cfg_mr[i] <= '0;
      prdata <= '0;
    end else if(psel && penable) begin
      if(pwrite) cfg_mr[paddr[4:2]] <= pwdata;
      else       prdata <= cfg_mr[paddr[4:2]];
    end
  end

  // AXI address front-end FIFOs, exactly 8 entries each.
  logic awf_wr, awf_rd, awf_full, awf_empty;
  logic [AWF_W-1:0] awf_dout;
  sync_fifo #(.WIDTH(AWF_W), .DEPTH(AXI_AW_FIFO_DEPTH)) u_aw_fifo (
    .clk(aclk), .rst_n(aresetn), .wr_en(awf_wr), .wr_data(s_axi_awaddr), .full(awf_full),
    .rd_en(awf_rd), .rd_data(awf_dout), .empty(awf_empty));

  logic arf_wr, arf_rd, arf_full, arf_empty;
  logic [AWF_W-1:0] arf_dout;
  sync_fifo #(.WIDTH(AWF_W), .DEPTH(AXI_AR_FIFO_DEPTH)) u_ar_fifo (
    .clk(aclk), .rst_n(aresetn), .wr_en(arf_wr), .wr_data(s_axi_araddr), .full(arf_full),
    .rd_en(arf_rd), .rd_data(arf_dout), .empty(arf_empty));

  assign s_axi_awready = !awf_full;
  assign awf_wr = s_axi_awvalid && s_axi_awready;
  assign s_axi_arready = !arf_full;
  assign arf_wr = s_axi_arvalid && s_axi_arready;

  req_t wr_req_in, rd_req_in;
  logic wr_req_wr, rd_req_wr, wr_req_full, rd_req_full, wr_req_afull, rd_req_afull;
  req_t wr_req_out, rd_req_out;
  logic wr_req_rd, rd_req_rd, wr_req_empty, rd_req_empty;

  assign wr_req_in = '{wr:1'b1, addr:awf_dout, wdata:s_axi_wdata, wstrb:s_axi_wstrb};
  assign rd_req_in = '{wr:1'b0, addr:arf_dout, wdata:'0, wstrb:'0};
  assign s_axi_wready = !awf_empty && !wr_req_full;
  assign wr_req_wr = s_axi_wvalid && s_axi_wready;
  assign awf_rd    = wr_req_wr;
  assign rd_req_wr = !arf_empty && !rd_req_full;
  assign arf_rd    = rd_req_wr;

  async_fifo #(.WIDTH(REQ_W), .DEPTH(REQ_FIFO_DEPTH)) u_wr_req_fifo (
    .wr_clk(aclk), .wr_rst_n(aresetn), .wr_en(wr_req_wr), .wr_data(wr_req_in), .wr_full(wr_req_full), .wr_almost_full(wr_req_afull),
    .rd_clk(ddr_clk), .rd_rst_n(ddr_resetn), .rd_en(wr_req_rd), .rd_data(wr_req_out), .rd_empty(wr_req_empty));

  async_fifo #(.WIDTH(REQ_W), .DEPTH(REQ_FIFO_DEPTH)) u_rd_req_fifo (
    .wr_clk(aclk), .wr_rst_n(aresetn), .wr_en(rd_req_wr), .wr_data(rd_req_in), .wr_full(rd_req_full), .wr_almost_full(rd_req_afull),
    .rd_clk(ddr_clk), .rd_rst_n(ddr_resetn), .rd_en(rd_req_rd), .rd_data(rd_req_out), .rd_empty(rd_req_empty));

  rsp_t rsp_in, rsp_out;
  logic rsp_wr, rsp_full, rsp_afull, rsp_rd, rsp_empty;
  async_fifo #(.WIDTH(RSP_W), .DEPTH(RSP_FIFO_DEPTH)) u_rsp_fifo (
    .wr_clk(ddr_clk), .wr_rst_n(ddr_resetn), .wr_en(rsp_wr), .wr_data(rsp_in), .wr_full(rsp_full), .wr_almost_full(rsp_afull),
    .rd_clk(aclk), .rd_rst_n(aresetn), .rd_en(rsp_rd), .rd_data(rsp_out), .rd_empty(rsp_empty));

  // AXI response steering. B and R channels are held independently.
  rsp_t rsp_hold;
  logic rsp_hold_v;
  always_ff @(posedge aclk or negedge aresetn) begin
    if(!aresetn) begin
      rsp_hold_v <= 1'b0; s_axi_bvalid <= 1'b0; s_axi_rvalid <= 1'b0;
      s_axi_bresp <= 2'b00; s_axi_rresp <= 2'b00; s_axi_rdata <= '0; s_axi_rlast <= 1'b1;
    end else begin
      if(s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if(s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
      if(!rsp_hold_v && !rsp_empty) begin
        rsp_hold <= rsp_out;
        rsp_hold_v <= 1'b1;
      end else if(rsp_hold_v) begin
        if(rsp_hold.wr && !s_axi_bvalid) begin
          s_axi_bresp <= rsp_hold.resp; s_axi_bvalid <= 1'b1; rsp_hold_v <= 1'b0;
        end else if(!rsp_hold.wr && !s_axi_rvalid) begin
          s_axi_rdata <= rsp_hold.rdata; s_axi_rresp <= rsp_hold.resp; s_axi_rlast <= 1'b1; s_axi_rvalid <= 1'b1; rsp_hold_v <= 1'b0;
        end
      end
    end
  end
  assign rsp_rd = !rsp_hold_v && !rsp_empty;

  // DRAM domain scheduler and 64-entry direct-mapped data cache.
  typedef enum logic [4:0] {S_RST,S_INIT_WAIT,S_MRS3,S_MRS6,S_MRS5,S_MRS4,S_MRS2,S_MRS1,S_MRS0,S_ZQCL,S_IDLE,S_ACT,S_TRCD,S_WR,S_RD,S_RLAT,S_PRE,S_TRP,S_RESP} state_t;
  state_t st;
  logic [15:0] timer;
  req_t cur_req;
  logic [DDR4_DQ_W-1:0] dq_out;
  logic dq_oe;

  logic [AXI_DATA_W-1:0] cache_data [0:CACHE_LINES-1];
  logic [AXI_ADDR_W-1:CACHE_IDX_W+2] cache_tag [0:CACHE_LINES-1];
  logic cache_valid [0:CACHE_LINES-1];
  logic [CACHE_IDX_W-1:0] cur_idx;
  logic cache_hit;
  assign cur_idx = cur_req.addr[CACHE_IDX_W+1:2];
  assign cache_hit = cache_valid[cur_idx] && (cache_tag[cur_idx] == cur_req.addr[AXI_ADDR_W-1:CACHE_IDX_W+2]);

  assign ddr4_ck_t = ddr_clk;
  assign ddr4_ck_c = ~ddr_clk;
  assign ddr4_reset_n = ddr_resetn;
  assign ddr4_dq = dq_oe ? dq_out : 'z;
  assign ddr4_dqs_t = dq_oe ? {DDR4_DQS_W{ddr_clk}} : 'z;
  assign ddr4_dqs_c = dq_oe ? {DDR4_DQS_W{~ddr_clk}} : 'z;

  function automatic [DDR4_BG_W-1:0] addr_bg(input logic [AXI_ADDR_W-1:0] a); return a[13:12]; endfunction
  function automatic [DDR4_BA_W-1:0] addr_ba(input logic [AXI_ADDR_W-1:0] a); return a[11:10]; endfunction
  function automatic [DDR4_ROW_W-1:0] addr_row(input logic [AXI_ADDR_W-1:0] a); return a[28:14]; endfunction
  function automatic [DDR4_COL_W-1:0] addr_col(input logic [AXI_ADDR_W-1:0] a); return a[9:0]; endfunction

  always_comb begin
    wr_req_rd = 1'b0; rd_req_rd = 1'b0; rsp_wr = 1'b0;
    if(st == S_IDLE && !rsp_full) begin
      // Read cycle has higher priority than write cycle.
      if(!rd_req_empty) rd_req_rd = 1'b1;
      else if(!wr_req_empty) wr_req_rd = 1'b1;
    end
    if(st == S_RESP && !rsp_full) rsp_wr = 1'b1;
  end

  task automatic drive_cmd(input ddr4_cmd_e cmd);
    begin
      ddr4_cs_n = 1'b0; ddr4_act_n = 1'b1; ddr4_ras_n = 1'b1; ddr4_cas_n = 1'b1; ddr4_we_n = 1'b1;
      unique case(cmd)
        DDR4_CMD_DES: begin ddr4_cs_n = 1'b1; end
        DDR4_CMD_ACT: begin ddr4_act_n = 1'b0; end
        DDR4_CMD_RD : begin ddr4_ras_n = 1'b1; ddr4_cas_n = 1'b0; ddr4_we_n = 1'b1; end
        DDR4_CMD_WR : begin ddr4_ras_n = 1'b1; ddr4_cas_n = 1'b0; ddr4_we_n = 1'b0; end
        DDR4_CMD_PRE: begin ddr4_ras_n = 1'b0; ddr4_cas_n = 1'b1; ddr4_we_n = 1'b0; end
        DDR4_CMD_REF: begin ddr4_ras_n = 1'b0; ddr4_cas_n = 1'b0; ddr4_we_n = 1'b1; end
        DDR4_CMD_MRS: begin ddr4_ras_n = 1'b0; ddr4_cas_n = 1'b0; ddr4_we_n = 1'b0; end
        DDR4_CMD_ZQCL:begin ddr4_ras_n = 1'b1; ddr4_cas_n = 1'b1; ddr4_we_n = 1'b0; ddr4_a[10] = 1'b1; end
        default: begin ddr4_cs_n = 1'b1; end
      endcase
    end
  endtask

  always_ff @(posedge ddr_clk or negedge ddr_resetn) begin
    if(!ddr_resetn) begin
      st <= S_RST; timer <= '0; cur_req <= '0; dq_out <= '0; dq_oe <= 1'b0;
      ddr4_cke <= 1'b0; ddr4_odt <= 1'b0; ddr4_dm_n <= '1;
      ddr4_cs_n <= 1'b1; ddr4_act_n <= 1'b1; ddr4_ras_n <= 1'b1; ddr4_cas_n <= 1'b1; ddr4_we_n <= 1'b1;
      ddr4_a <= '0; ddr4_ba <= '0; ddr4_bg <= '0;
      for(int i=0;i<CACHE_LINES;i++) begin cache_valid[i] <= 1'b0; cache_data[i] <= '0; cache_tag[i] <= '0; end
    end else begin
      drive_cmd(DDR4_CMD_DES);
      dq_oe <= 1'b0; ddr4_cke <= 1'b1; ddr4_odt <= 1'b1; ddr4_dm_n <= '1;
      if(timer != 0) timer <= timer - 1'b1;

      unique case(st)
        S_RST: begin timer <= INIT_CK; st <= S_INIT_WAIT; end
        S_INIT_WAIT: if(timer==0) st <= S_MRS3;
        S_MRS3,S_MRS6,S_MRS5,S_MRS4,S_MRS2,S_MRS1,S_MRS0: begin
          drive_cmd(DDR4_CMD_MRS); ddr4_ba <= st[1:0]; ddr4_bg <= '0; ddr4_a <= cfg_mr[st[2:0]][DDR4_ADDR_W-1:0]; timer <= 4; st <= (st==S_MRS0) ? S_ZQCL : state_t'(st + 1'b1);
        end
        S_ZQCL: begin drive_cmd(DDR4_CMD_ZQCL); timer <= 16; st <= S_IDLE; end
        S_IDLE: begin
          if(!rsp_full) begin
            if(!rd_req_empty) begin cur_req <= rd_req_out; st <= S_ACT; end
            else if(!wr_req_empty) begin cur_req <= wr_req_out; st <= S_ACT; end
          end
        end
        S_ACT: begin
          ddr4_bg <= addr_bg(cur_req.addr); ddr4_ba <= addr_ba(cur_req.addr); ddr4_a <= {{(DDR4_ADDR_W-DDR4_ROW_W){1'b0}},addr_row(cur_req.addr)};
          drive_cmd(DDR4_CMD_ACT); timer <= T_RCD_CK; st <= S_TRCD;
        end
        S_TRCD: if(timer==0) st <= cur_req.wr ? S_WR : (cache_hit ? S_RESP : S_RD);
        S_WR: begin
          ddr4_bg <= addr_bg(cur_req.addr); ddr4_ba <= addr_ba(cur_req.addr); ddr4_a <= {{(DDR4_ADDR_W-DDR4_COL_W){1'b0}},addr_col(cur_req.addr)};
          ddr4_dm_n <= ~cur_req.wstrb[DDR4_DQS_W-1:0]; dq_out <= cur_req.wdata[DDR4_DQ_W-1:0]; dq_oe <= 1'b1; drive_cmd(DDR4_CMD_WR);
          cache_data[cur_idx] <= cur_req.wdata; cache_tag[cur_idx] <= cur_req.addr[AXI_ADDR_W-1:CACHE_IDX_W+2]; cache_valid[cur_idx] <= 1'b1;
          timer <= 4; st <= S_PRE;
        end
        S_RD: begin
          ddr4_bg <= addr_bg(cur_req.addr); ddr4_ba <= addr_ba(cur_req.addr); ddr4_a <= {{(DDR4_ADDR_W-DDR4_COL_W){1'b0}},addr_col(cur_req.addr)};
          drive_cmd(DDR4_CMD_RD); timer <= CL_CK; st <= S_RLAT;
        end
        S_RLAT: if(timer==0) begin
          cache_data[cur_idx] <= {{(AXI_DATA_W-DDR4_DQ_W){1'b0}},ddr4_dq}; cache_tag[cur_idx] <= cur_req.addr[AXI_ADDR_W-1:CACHE_IDX_W+2]; cache_valid[cur_idx] <= 1'b1;
          st <= S_PRE;
        end
        S_PRE: begin ddr4_a[10] <= 1'b1; drive_cmd(DDR4_CMD_PRE); timer <= T_RP_CK; st <= S_TRP; end
        S_TRP: if(timer==0) st <= S_RESP;
        S_RESP: if(!rsp_full) st <= S_IDLE;
        default: st <= S_RST;
      endcase
    end
  end

  always_comb begin
    if(cur_req.wr) rsp_in = '{wr:1'b1, addr:cur_req.addr, rdata:'0, resp:2'b00};
    else if(cache_hit) rsp_in = '{wr:1'b0, addr:cur_req.addr, rdata:cache_data[cur_idx], resp:2'b00};
    else rsp_in = '{wr:1'b0, addr:cur_req.addr, rdata:cache_data[cur_idx], resp:2'b00};
  end
endmodule
