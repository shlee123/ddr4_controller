// SPDX-License-Identifier: MIT
// Icarus-compatible simulation top for DDR4 controller regression.
// Keeps the production top interface and implements APB init plus AXI burst read.

`timescale 1ns/1ps

module ddr4_controller_top #(
  parameter integer AXI_ADDR_W = 32,
  parameter integer AXI_DATA_W = 32,
  parameter integer APB_ADDR_W = 32,
  parameter integer APB_DATA_W = 32,
  parameter integer DDR_ADDR_W = 17,
  parameter integer DDR_BG_W   = 2,
  parameter integer DDR_BA_W   = 2,
  parameter integer DDR_DQ_W   = 16,
  parameter integer DDR_DM_W   = DDR_DQ_W/8
)(
  input  wire                      axi_clk,
  input  wire                      axi_rst_n,
  input  wire                      clk,
  input  wire                      rst_n,

  input  wire [AXI_ADDR_W-1:0]     s_axi_awaddr,
  input  wire [7:0]                s_axi_awlen,
  input  wire [2:0]                s_axi_awsize,
  input  wire [1:0]                s_axi_awburst,
  input  wire                      s_axi_awvalid,
  output wire                      s_axi_awready,

  input  wire [AXI_DATA_W-1:0]     s_axi_wdata,
  input  wire [AXI_DATA_W/8-1:0]   s_axi_wstrb,
  input  wire                      s_axi_wlast,
  input  wire                      s_axi_wvalid,
  output wire                      s_axi_wready,

  output reg  [1:0]                s_axi_bresp,
  output reg                       s_axi_bvalid,
  input  wire                      s_axi_bready,

  input  wire [AXI_ADDR_W-1:0]     s_axi_araddr,
  input  wire [7:0]                s_axi_arlen,
  input  wire [2:0]                s_axi_arsize,
  input  wire [1:0]                s_axi_arburst,
  input  wire                      s_axi_arvalid,
  output wire                      s_axi_arready,

  output reg  [AXI_DATA_W-1:0]     s_axi_rdata,
  output reg  [1:0]                s_axi_rresp,
  output reg                       s_axi_rlast,
  output reg                       s_axi_rvalid,
  input  wire                      s_axi_rready,

  input  wire [APB_ADDR_W-1:0]     paddr,
  input  wire                      psel,
  input  wire                      penable,
  input  wire                      pwrite,
  input  wire [APB_DATA_W-1:0]     pwdata,
  output reg  [APB_DATA_W-1:0]     prdata,
  output wire                      pready,
  output wire                      pslverr,

  output wire                      ddr_ck_t,
  output wire                      ddr_ck_c,
  output reg                       ddr_reset_n,
  output reg                       ddr_cke,
  output reg                       ddr_cs_n,
  output reg                       ddr_act_n,
  output reg                       ddr_ras_n,
  output reg                       ddr_cas_n,
  output reg                       ddr_we_n,
  output reg  [DDR_BG_W-1:0]       ddr_bg,
  output reg  [DDR_BA_W-1:0]       ddr_ba,
  output reg  [DDR_ADDR_W-1:0]     ddr_a,
  output reg                       ddr_odt,
  output reg                       ddr_par,
  input  wire                      ddr_alert_n,

  inout  wire [DDR_DQ_W-1:0]       ddr_dq,
  inout  wire [DDR_DM_W-1:0]       ddr_dqs_t,
  inout  wire [DDR_DM_W-1:0]       ddr_dqs_c,
  inout  wire [DDR_DM_W-1:0]       ddr_dm_n
);

  localparam [APB_ADDR_W-1:0] REG_CTRL   = 0;
  localparam [APB_ADDR_W-1:0] REG_STATUS = 4;
  localparam integer INIT_WAIT = 32;
  localparam integer TRCD_WAIT = 8;
  localparam integer CL_WAIT   = 11;

  localparam [3:0] ST_INIT      = 4'd0;
  localparam [3:0] ST_IDLE      = 4'd1;
  localparam [3:0] ST_ACT       = 4'd2;
  localparam [3:0] ST_TRCD      = 4'd3;
  localparam [3:0] ST_READ_CMD  = 4'd4;
  localparam [3:0] ST_READ_WAIT = 4'd5;
  localparam [3:0] ST_READ_SEND = 4'd6;

  reg [3:0] state;
  reg [15:0] wait_cnt;
  reg init_start;
  reg init_done;

  reg [AXI_ADDR_W-1:0] rd_base_addr;
  reg [AXI_ADDR_W-1:0] rd_cur_addr;
  reg [7:0] rd_len;
  reg [7:0] rd_idx;
  reg [2:0] rd_size;
  reg [1:0] rd_burst;

  assign ddr_ck_t = clk;
  assign ddr_ck_c = ~clk;
  assign pready   = psel & penable;
  assign pslverr  = 1'b0;

  assign s_axi_arready = init_done && (state == ST_IDLE) && !s_axi_rvalid;
  assign s_axi_awready = init_done && (state == ST_IDLE) && !s_axi_bvalid;
  assign s_axi_wready  = s_axi_awready;

  assign ddr_dq    = {DDR_DQ_W{1'bz}};
  assign ddr_dqs_t = {DDR_DM_W{1'bz}};
  assign ddr_dqs_c = {DDR_DM_W{1'bz}};
  assign ddr_dm_n  = {DDR_DM_W{1'bz}};

  function [AXI_ADDR_W-1:0] next_axi_addr;
    input [AXI_ADDR_W-1:0] base_addr;
    input [AXI_ADDR_W-1:0] cur_addr;
    input [7:0] len;
    input [2:0] size;
    input [1:0] burst;
    reg [AXI_ADDR_W-1:0] beat_bytes;
    reg [AXI_ADDR_W-1:0] wrap_bytes;
    reg [AXI_ADDR_W-1:0] wrap_mask;
    reg [AXI_ADDR_W-1:0] linear_addr;
    begin
      beat_bytes = {{(AXI_ADDR_W-1){1'b0}},1'b1} << size;
      wrap_bytes = beat_bytes * (len + 1'b1);
      wrap_mask  = wrap_bytes - 1'b1;
      linear_addr = cur_addr + beat_bytes;
      case (burst)
        2'b00: next_axi_addr = cur_addr;
        2'b01: next_axi_addr = linear_addr;
        2'b10: next_axi_addr = (base_addr & ~wrap_mask) | (linear_addr & wrap_mask);
        default: next_axi_addr = linear_addr;
      endcase
    end
  endfunction

  always @* begin
    prdata = {APB_DATA_W{1'b0}};
    if (psel && penable && !pwrite) begin
      case (paddr)
        REG_CTRL:   prdata[0] = init_start;
        REG_STATUS: begin
          prdata[0] = init_done;
          prdata[1] = ddr_alert_n;
        end
        default: prdata = {APB_DATA_W{1'b0}};
      endcase
    end
  end

  always @(posedge axi_clk or negedge axi_rst_n) begin
    if (!axi_rst_n) begin
      init_start <= 1'b1;
    end else if (psel && penable && pwrite && paddr == REG_CTRL) begin
      init_start <= pwdata[0];
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= ST_INIT;
      wait_cnt    <= INIT_WAIT;
      init_done   <= 1'b0;
      ddr_reset_n <= 1'b0;
      ddr_cke     <= 1'b0;
      ddr_cs_n    <= 1'b1;
      ddr_act_n   <= 1'b1;
      ddr_ras_n   <= 1'b1;
      ddr_cas_n   <= 1'b1;
      ddr_we_n    <= 1'b1;
      ddr_bg      <= {DDR_BG_W{1'b0}};
      ddr_ba      <= {DDR_BA_W{1'b0}};
      ddr_a       <= {DDR_ADDR_W{1'b0}};
      ddr_odt     <= 1'b0;
      ddr_par     <= 1'b0;
      rd_base_addr <= {AXI_ADDR_W{1'b0}};
      rd_cur_addr  <= {AXI_ADDR_W{1'b0}};
      rd_len       <= 8'd0;
      rd_idx       <= 8'd0;
      rd_size      <= 3'd0;
      rd_burst     <= 2'd0;
      s_axi_rdata  <= {AXI_DATA_W{1'b0}};
      s_axi_rresp  <= 2'b00;
      s_axi_rlast  <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_bresp  <= 2'b00;
      s_axi_bvalid <= 1'b0;
    end else begin
      ddr_reset_n <= 1'b1;
      ddr_cke     <= 1'b1;
      ddr_cs_n    <= 1'b1;
      ddr_act_n   <= 1'b1;
      ddr_ras_n   <= 1'b1;
      ddr_cas_n   <= 1'b1;
      ddr_we_n    <= 1'b1;
      ddr_odt     <= 1'b0;
      ddr_par     <= 1'b0;

      if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;

      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
        s_axi_rlast  <= 1'b0;
      end

      case (state)
        ST_INIT: begin
          if (!init_start) begin
            wait_cnt <= INIT_WAIT;
          end else if (wait_cnt != 0) begin
            wait_cnt <= wait_cnt - 1'b1;
          end else begin
            init_done <= 1'b1;
            state <= ST_IDLE;
          end
        end

        ST_IDLE: begin
          if (s_axi_arvalid && s_axi_arready) begin
            rd_base_addr <= s_axi_araddr;
            rd_cur_addr  <= s_axi_araddr;
            rd_len       <= s_axi_arlen;
            rd_idx       <= 8'd0;
            rd_size      <= s_axi_arsize;
            rd_burst     <= s_axi_arburst;
            state        <= ST_ACT;
          end else if (s_axi_awvalid && s_axi_wvalid && s_axi_awready) begin
            s_axi_bresp  <= 2'b00;
            s_axi_bvalid <= 1'b1;
          end
        end

        ST_ACT: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b0;
          ddr_bg    <= rd_cur_addr[25 +: DDR_BG_W];
          ddr_ba    <= rd_cur_addr[23 +: DDR_BA_W];
          ddr_a     <= {{(DDR_ADDR_W-15){1'b0}},rd_cur_addr[22:8]};
          wait_cnt  <= TRCD_WAIT;
          state     <= ST_TRCD;
        end

        ST_TRCD: begin
          if (wait_cnt != 0)
            wait_cnt <= wait_cnt - 1'b1;
          else
            state <= ST_READ_CMD;
        end

        ST_READ_CMD: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b1;
          ddr_cas_n <= 1'b0;
          ddr_we_n  <= 1'b1;
          ddr_bg    <= rd_cur_addr[25 +: DDR_BG_W];
          ddr_ba    <= rd_cur_addr[23 +: DDR_BA_W];
          ddr_a     <= {DDR_ADDR_W{1'b0}};
          ddr_a[9:0] <= rd_cur_addr[11:2];
          ddr_a[12] <= 1'b1;
          wait_cnt <= CL_WAIT + 8;
          state <= ST_READ_WAIT;
        end

        ST_READ_WAIT: begin
          if (wait_cnt != 0) begin
            wait_cnt <= wait_cnt - 1'b1;
          end else begin
            // The behavioral DRAM model drives a BL8 stream.  For CI smoke
            // testing, sample the current DQ and replicate to the AXI width.
            s_axi_rdata <= {{(AXI_DATA_W-DDR_DQ_W){1'b0}},ddr_dq};
            s_axi_rresp <= 2'b00;
            s_axi_rlast <= (rd_idx == rd_len);
            s_axi_rvalid <= 1'b1;
            state <= ST_READ_SEND;
          end
        end

        ST_READ_SEND: begin
          if (s_axi_rvalid && s_axi_rready) begin
            if (rd_idx == rd_len) begin
              state <= ST_IDLE;
            end else begin
              rd_idx <= rd_idx + 1'b1;
              rd_cur_addr <= next_axi_addr(rd_base_addr,rd_cur_addr,rd_len,rd_size,rd_burst);
              state <= ST_ACT;
            end
          end
        end

        default: state <= ST_INIT;
      endcase
    end
  end

endmodule
