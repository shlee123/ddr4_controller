// SPDX-License-Identifier: MIT
// Version 2 DDR4 DQ/DQS burst-data PHY shim.
//
// Synthesis-oriented controller-side burst shim.
// This module keeps I/O-cell-specific behavior at the top boundary through
// explicit output, output-enable, and input signals.  No internal tri-state is used.

`timescale 1ns/1ps

import ddr4_ctrl_pkg::*;

module ddr4_dq_dqs_phy #(
  parameter int DQ_W     = DDR_DQ_W,
  parameter int DM_W     = DDR_DM_W,
  parameter int BURST_UI = DDR_BL8_UI,
  parameter int CL_CK    = T_CL_CK,
  parameter int CWL_CK   = T_CWL_CK
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

  input  logic [DQ_W-1:0]              dq_in,
  output logic [DQ_W-1:0]              dq_out,
  output logic                         dq_oe,
  output logic [DM_W-1:0]              dm_out,
  output logic                         dm_oe,
  output logic [DM_W-1:0]              dqs_t_out,
  output logic [DM_W-1:0]              dqs_c_out,
  output logic                         dqs_oe
);

  typedef enum logic [1:0] {
    PHY_IDLE,
    PHY_WLAT,
    PHY_WBURST,
    PHY_RLAT
  } phy_state_e;

  phy_state_e state;
  logic [7:0] latency_cnt;
  logic [3:0] ui_cnt;
  logic [DQ_W*BURST_UI-1:0] rd_shift;

  function automatic logic [DQ_W-1:0] select_dq_ui(
    input logic [DQ_W*BURST_UI-1:0] data,
    input logic [3:0] ui
  );
    logic [DQ_W-1:0] selected;
    begin
      selected = '0;
      for (int i = 0; i < BURST_UI; i++) begin
        if (ui == i[3:0]) begin
          selected = data[i*DQ_W +: DQ_W];
        end
      end
      return selected;
    end
  endfunction

  function automatic logic [DM_W-1:0] select_dm_ui(
    input logic [DM_W*BURST_UI-1:0] data,
    input logic [3:0] ui
  );
    logic [DM_W-1:0] selected;
    begin
      selected = '1;
      for (int i = 0; i < BURST_UI; i++) begin
        if (ui == i[3:0]) begin
          selected = data[i*DM_W +: DM_W];
        end
      end
      return selected;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= PHY_IDLE;
      latency_cnt <= 8'd0;
      ui_cnt      <= 4'd0;
      dq_out      <= '0;
      dm_out      <= '1;
      dq_oe       <= 1'b0;
      dm_oe       <= 1'b0;
      dqs_t_out   <= '0;
      dqs_c_out   <= '1;
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
          dq_oe       <= 1'b0;
          dm_oe       <= 1'b0;
          dqs_oe      <= 1'b0;
          dqs_t_out   <= '0;
          dqs_c_out   <= '1;
          wr_busy     <= 1'b0;
          rd_busy     <= 1'b0;
          ui_cnt      <= 4'd0;
          latency_cnt <= 8'd0;

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
          if (latency_cnt != 8'd0) begin
            latency_cnt <= latency_cnt - 8'd1;
          end else begin
            state  <= PHY_WBURST;
            dq_oe  <= 1'b1;
            dm_oe  <= 1'b1;
            dqs_oe <= 1'b1;
            ui_cnt <= 4'd0;
          end
        end

        PHY_WBURST: begin
          wr_busy   <= 1'b1;
          dq_out    <= select_dq_ui(wr_data, ui_cnt);
          dm_out    <= select_dm_ui(wr_dm_n, ui_cnt);
          dqs_t_out <= {DM_W{ui_cnt[0]}};
          dqs_c_out <= {DM_W{~ui_cnt[0]}};

          if (ui_cnt == (BURST_UI-1)) begin
            state   <= PHY_IDLE;
            dq_oe   <= 1'b0;
            dm_oe   <= 1'b0;
            dqs_oe  <= 1'b0;
            wr_done <= 1'b1;
          end else begin
            ui_cnt <= ui_cnt + 4'd1;
          end
        end

        PHY_RLAT: begin
          rd_busy <= 1'b1;
          if (latency_cnt != 8'd0) begin
            latency_cnt <= latency_cnt - 8'd1;
          end else begin
            rd_shift[ui_cnt*DQ_W +: DQ_W] <= dq_in;
            if (ui_cnt == (BURST_UI-1)) begin
              rd_data  <= rd_shift;
              rd_data[ui_cnt*DQ_W +: DQ_W] <= dq_in;
              rd_valid <= 1'b1;
              rd_busy  <= 1'b0;
              state    <= PHY_IDLE;
            end else begin
              ui_cnt <= ui_cnt + 4'd1;
            end
          end
        end

        default: begin
          state <= PHY_IDLE;
        end
      endcase
    end
  end

endmodule : ddr4_dq_dqs_phy
