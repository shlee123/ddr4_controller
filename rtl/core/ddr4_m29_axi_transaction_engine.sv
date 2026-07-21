// SPDX-License-Identifier: MIT
// M29: AXI front-end to M23-M28 native transaction engine integration.
`timescale 1ns/1ps

module ddr4_m29_axi_transaction_engine #(
  parameter integer ADDR_W=32,
  parameter integer DATA_W=32,
  parameter integer ID_W=6,
  parameter integer TAG_W=4,
  parameter integer AW_DEPTH=4,
  parameter integer OUTSTANDING=16,
  parameter integer REQ_DEPTH=8,
  parameter integer CMD_DEPTH=16,
  parameter integer RSP_DEPTH=16,
  parameter integer T_REFI=64,
  parameter integer T_RFC=12
)(
  input  wire                  clk,
  input  wire                  rst_n,

  input  wire [ID_W-1:0]       s_axi_awid,
  input  wire [ADDR_W-1:0]     s_axi_awaddr,
  input  wire [7:0]            s_axi_awlen,
  input  wire [2:0]            s_axi_awsize,
  input  wire [1:0]            s_axi_awburst,
  input  wire                  s_axi_awvalid,
  output wire                  s_axi_awready,

  input  wire [DATA_W-1:0]     s_axi_wdata,
  input  wire [DATA_W/8-1:0]   s_axi_wstrb,
  input  wire                  s_axi_wlast,
  input  wire                  s_axi_wvalid,
  output wire                  s_axi_wready,

  output wire [ID_W-1:0]       s_axi_bid,
  output wire [1:0]            s_axi_bresp,
  output wire                  s_axi_bvalid,
  input  wire                  s_axi_bready,

  input  wire [ID_W-1:0]       s_axi_arid,
  input  wire [ADDR_W-1:0]     s_axi_araddr,
  input  wire [7:0]            s_axi_arlen,
  input  wire [2:0]            s_axi_arsize,
  input  wire [1:0]            s_axi_arburst,
  input  wire                  s_axi_arvalid,
  output wire                  s_axi_arready,

  output wire [ID_W-1:0]       s_axi_rid,
  output wire [DATA_W-1:0]     s_axi_rdata,
  output wire [1:0]            s_axi_rresp,
  output wire                  s_axi_rlast,
  output wire                  s_axi_rvalid,
  input  wire                  s_axi_rready,

  output wire                  native_cmd_valid,
  input  wire                  native_cmd_ready,
  output wire [TAG_W-1:0]      native_cmd_tag,
  output wire                  native_cmd_write,
  output wire [ID_W-1:0]       native_cmd_id,
  output wire [ADDR_W-1:0]     native_cmd_addr,
  output wire [7:0]            native_cmd_beat,
  output wire                  native_cmd_last,

  input  wire                  native_cpl_valid,
  input  wire [TAG_W-1:0]      native_cpl_tag,
  input  wire [DATA_W-1:0]     native_cpl_rdata,
  input  wire [1:0]            native_cpl_resp,

  output wire                  refresh_req,
  input  wire                  refresh_ack,
  output wire                  refresh_block,
  output wire [7:0]            outstanding_count,
  output wire [7:0]            command_count,
  output wire                  protocol_error,
  output wire                  refresh_deadline_error,
  output reg                   axi_write_protocol_error
);
  localparam integer AW_AW = $clog2(AW_DEPTH);

  reg [ID_W-1:0]   aw_id_mem    [0:AW_DEPTH-1];
  reg [ADDR_W-1:0] aw_addr_mem  [0:AW_DEPTH-1];
  reg [7:0]        aw_len_mem   [0:AW_DEPTH-1];
  reg [2:0]        aw_size_mem  [0:AW_DEPTH-1];
  reg [1:0]        aw_burst_mem [0:AW_DEPTH-1];
  reg [AW_AW-1:0]  aw_wp;
  reg [AW_AW-1:0]  aw_rp;
  reg [AW_AW:0]    aw_count;
  reg [7:0]        w_beat_count;

  reg              wr_desc_valid;
  reg [ID_W-1:0]   wr_desc_id;
  reg [ADDR_W-1:0] wr_desc_addr;
  reg [7:0]        wr_desc_len;
  reg [2:0]        wr_desc_size;
  reg [1:0]        wr_desc_burst;

  wire aw_push = s_axi_awvalid && s_axi_awready;
  wire w_push  = s_axi_wvalid && s_axi_wready;
  wire w_expected_last = (w_beat_count == aw_len_mem[aw_rp]);
  wire w_finish = w_push && s_axi_wlast;

  assign s_axi_awready = (aw_count < AW_DEPTH);
  assign s_axi_wready  = (aw_count != 0) && !wr_desc_valid;

  wire req_valid;
  wire req_ready;
  wire req_write;
  wire [ID_W-1:0] req_id;
  wire [ADDR_W-1:0] req_addr;
  wire [7:0] req_len;
  wire [2:0] req_size;
  wire [1:0] req_burst;
  wire req_accept = req_valid && req_ready;

  assign req_valid = wr_desc_valid || s_axi_arvalid;
  assign req_write = wr_desc_valid;
  assign req_id    = wr_desc_valid ? wr_desc_id    : s_axi_arid;
  assign req_addr  = wr_desc_valid ? wr_desc_addr  : s_axi_araddr;
  assign req_len   = wr_desc_valid ? wr_desc_len   : s_axi_arlen;
  assign req_size  = wr_desc_valid ? wr_desc_size  : s_axi_arsize;
  assign req_burst = wr_desc_valid ? wr_desc_burst : s_axi_arburst;
  assign s_axi_arready = !wr_desc_valid && req_ready;

  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_wp <= 0;
      aw_rp <= 0;
      aw_count <= 0;
      w_beat_count <= 0;
      wr_desc_valid <= 0;
      wr_desc_id <= 0;
      wr_desc_addr <= 0;
      wr_desc_len <= 0;
      wr_desc_size <= 0;
      wr_desc_burst <= 0;
      axi_write_protocol_error <= 0;
      for (i=0;i<AW_DEPTH;i=i+1) begin
        aw_id_mem[i] <= 0;
        aw_addr_mem[i] <= 0;
        aw_len_mem[i] <= 0;
        aw_size_mem[i] <= 0;
        aw_burst_mem[i] <= 0;
      end
    end else begin
      if (aw_push) begin
        aw_id_mem[aw_wp] <= s_axi_awid;
        aw_addr_mem[aw_wp] <= s_axi_awaddr;
        aw_len_mem[aw_wp] <= s_axi_awlen;
        aw_size_mem[aw_wp] <= s_axi_awsize;
        aw_burst_mem[aw_wp] <= s_axi_awburst;
        aw_wp <= aw_wp + 1'b1;
      end

      if (w_push) begin
        if (s_axi_wlast != w_expected_last)
          axi_write_protocol_error <= 1'b1;
        if (s_axi_wlast) begin
          wr_desc_valid <= 1'b1;
          wr_desc_id <= aw_id_mem[aw_rp];
          wr_desc_addr <= aw_addr_mem[aw_rp];
          wr_desc_len <= aw_len_mem[aw_rp];
          wr_desc_size <= aw_size_mem[aw_rp];
          wr_desc_burst <= aw_burst_mem[aw_rp];
          aw_rp <= aw_rp + 1'b1;
          w_beat_count <= 0;
        end else begin
          w_beat_count <= w_beat_count + 1'b1;
        end
      end

      if (req_accept && wr_desc_valid)
        wr_desc_valid <= 1'b0;

      case ({aw_push,w_finish})
        2'b10: aw_count <= aw_count + 1'b1;
        2'b01: aw_count <= aw_count - 1'b1;
        default: aw_count <= aw_count;
      endcase
    end
  end

  // WDATA/WSTRB are deliberately consumed by the AXI front-end here. M29 closes
  // the control-path integration; the native data-buffer attachment remains a
  // separate datapath concern and does not alter transaction identity/order.
  wire unused_wdata = ^s_axi_wdata ^ ^s_axi_wstrb;

  ddr4_m23_m28_engine #(
    .ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W),.TAG_W(TAG_W),
    .OUTSTANDING(OUTSTANDING),.REQ_DEPTH(REQ_DEPTH),
    .CMD_DEPTH(CMD_DEPTH),.RSP_DEPTH(RSP_DEPTH),
    .T_REFI(T_REFI),.T_RFC(T_RFC)
  ) u_transaction_engine (
    .clk(clk),.rst_n(rst_n),
    .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),
    .req_id(req_id),.req_addr(req_addr),.req_len(req_len),
    .req_size(req_size),.req_burst(req_burst),
    .cmd_valid(native_cmd_valid),.cmd_ready(native_cmd_ready),
    .cmd_tag(native_cmd_tag),.cmd_write(native_cmd_write),
    .cmd_id(native_cmd_id),.cmd_addr(native_cmd_addr),
    .cmd_beat(native_cmd_beat),.cmd_last(native_cmd_last),
    .cpl_valid(native_cpl_valid),.cpl_tag(native_cpl_tag),
    .cpl_rdata(native_cpl_rdata),.cpl_resp(native_cpl_resp),
    .b_valid(s_axi_bvalid),.b_ready(s_axi_bready),
    .b_id(s_axi_bid),.b_resp(s_axi_bresp),
    .r_valid(s_axi_rvalid),.r_ready(s_axi_rready),
    .r_id(s_axi_rid),.r_data(s_axi_rdata),
    .r_resp(s_axi_rresp),.r_last(s_axi_rlast),
    .refresh_req(refresh_req),.refresh_ack(refresh_ack),
    .refresh_block(refresh_block),
    .outstanding_count(outstanding_count),.command_count(command_count),
    .protocol_error(protocol_error),
    .refresh_deadline_error(refresh_deadline_error)
  );
endmodule
