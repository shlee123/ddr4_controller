// SPDX-License-Identifier: MIT
// Version 2 DDR4 DQ/DQS burst-data PHY shim.
//
// This is a synthesizable controller-side burst shim used by the VCS model.
// It abstracts the real FPGA/ASIC DDR I/O cells but preserves the DDR4 BL8
// concept: eight DQ unit intervals per READ/WRITE burst, with DQS toggling
// during WRITE and data captured during READ.

`timescale 1ns/1ps

import ddr4_ctrl_pkg::*;

module ddr4_dq_dqs_phy #(
  parameter int DQ_W   = DDR_DQ_W,
  parameter int DM_W   = DDR_DM_W,
  parameter int BURST_UI = DDR_BL8_UI,
  parameter int CL_CK  = T_CL_CK,
  parameter int CWL_CK = T_CWL_CK
)(
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         wr_start,
  input  logic [DQ_W*BURST_UI-1:0]     wr_data,
  input  logic [DM_W*BURST_UI-1:0]     wr_dm_n,
  output logic                         wr_busy,
  output logic                         wr_done,

  input  logic                         rd_start,
  output logic [DQ_W*BURST_UI-1:0]     rd_data,
  output logic                         rd_valid,
  output logic                         rd_busy,

  inout  wire  [DQ_W-1:0]              ddr_dq,
  inout  wire  [DM_W-1:0]              ddr_dqs_t,
  inout  wire  [DM_W-1:0]              ddr_dqs_c,
  inout  wire  [DM_W-1:0]              ddr_dm_n
);

  typedef enum logic [1:0] {
    PHY_IDLE,
    PHY_WLAT,
    PHY_WBURST,
    PHY_RLAT
  } phy_state_e;

  phy_state_e state;
  logic [7:0] latency_cnt;
  logic [$clog2(BURST_UI+1)-1:0] ui_cnt;
  logic [DQ_W-1:0] dq_out;
  logic [DM_W-1:0] dm_out;
  logic            dq_oe;
  logic            dqs_oe;
  logic [DQ_W*BURST_UI-1:0] rd_shift;

  assign ddr_dq    = dq_oe  ? dq_out : 'z;
  assign ddr_dm_n  = dq_oe  ? dm_out : 'z;
  assign ddr_dqs_t = dqs_oe ? {DM_W{clk}} : 'z;
  assign ddr_dqs_c = dqs_oe ? {DM_W{~clk}} : 'z;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= PHY_IDLE;
      latency_cnt <= '0;
      ui_cnt      <= '0;
      dq_out      <= '0;
      dm_out      <= '1;
      dq_oe       <= 1'b0;
      dqs_oe      <= 1'b0;
      wr_busy     <= 1'b0;
      wr_done     <= 1'b0;
      rd_busy     <= 1'b0;
      rd_valid    <= 1'b0;
      rd_data     <= '0;
      rd_shift    <= '0;
    end else begin
      wr_done  <= 1'b0;
      rd_valid <= 1'b0;

      unique case (state)
        PHY_IDLE: begin
          dq_oe   <= 1'b0;
          dqs_oe  <= 1'b0;
          wr_busy <= 1'b0;
          rd_busy <= 1'b0;
          ui_cnt  <= '0;

          if (wr_start) begin
            state       <= PHY_WLAT;
            latency_cnt <= CWL_CK[7:0];
            wr_busy     <= 1'b1;
          end else if (rd_start) begin
            state       <= PHY_RLAT;
            latency_cnt <= CL_CK[7:0];
            rd_busy     <= 1'b1;
            rd_shift    <= '0;
          end
        end

        PHY_WLAT: begin
          wr_busy <= 1'b1;
          if (latency_cnt != 0) begin
            latency_cnt <= latency_cnt - 1'b1;
          end else begin
            state  <= PHY_WBURST;
            dq_oe  <= 1'b1;
            dqs_oe <= 1'b1;
            ui_cnt <= '0;
          end
        end

        PHY_WBURST: begin
          wr_busy <= 1'b1;
          dq_out  <= wr_data[ui_cnt*DQ_W +: DQ_W];
          dm_out  <= wr_dm_n[ui_cnt*DM_W +: DM_W];
          if (ui_cnt == BURST_UI-1) begin
            state   <= PHY_IDLE;
            dq_oe   <= 1'b0;
            dqs_oe  <= 1'b0;
            wr_done <= 1'b1;
          end else begin
            ui_cnt <= ui_cnt + 1'b1;
          end
        end

        PHY_RLAT: begin
          rd_busy <= 1'b1;
          if (latency_cnt != 0) begin
            latency_cnt <= latency_cnt - 1'b1;
          end else begin
            rd_shift[ui_cnt*DQ_W +: DQ_W] <= ddr_dq;
            if (ui_cnt == BURST_UI-1) begin
              rd_data  <= rd_shift;
              rd_data[ui_cnt*DQ_W +: DQ_W] <= ddr_dq;
              rd_valid <= 1'b1;
              rd_busy  <= 1'b0;
              state    <= PHY_IDLE;
            end else begin
              ui_cnt <= ui_cnt + 1'b1;
            end
          end
        end

        default: state <= PHY_IDLE;
      endcase
    end
  end

endmodule : ddr4_dq_dqs_phy
