// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_phy_training #(
  parameter int RESET_CK = 8,
  parameter int WRITE_LEVEL_CK = 16,
  parameter int READ_GATE_CK = 16,
  parameter int READ_EYE_CK = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic phy_sample_ok,
  output logic busy,
  output logic done,
  output logic fail,
  output logic write_level_en,
  output logic read_gate_en,
  output logic read_eye_en,
  output logic [2:0] phase
);
  typedef enum logic [2:0] {IDLE, RESET_WAIT, WRITE_LEVEL, READ_GATE, READ_EYE, COMPLETE, FAILED} state_t;
  state_t state;
  integer count;
  logic stage_seen_ok;

  assign phase = state;
  assign busy = (state != IDLE) && (state != COMPLETE) && (state != FAILED);
  assign done = (state == COMPLETE);
  assign fail = (state == FAILED);
  assign write_level_en = (state == WRITE_LEVEL);
  assign read_gate_en   = (state == READ_GATE);
  assign read_eye_en    = (state == READ_EYE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      count <= 0;
      stage_seen_ok <= 1'b0;
    end else begin
      case (state)
        IDLE: if (start) begin state <= RESET_WAIT; count <= RESET_CK; stage_seen_ok <= 1'b0; end
        RESET_WAIT: begin
          if (count == 0) begin state <= WRITE_LEVEL; count <= WRITE_LEVEL_CK; stage_seen_ok <= 1'b0; end
          else count <= count - 1;
        end
        WRITE_LEVEL: begin
          if (phy_sample_ok) stage_seen_ok <= 1'b1;
          if (count == 0) begin
            if (stage_seen_ok || phy_sample_ok) begin state <= READ_GATE; count <= READ_GATE_CK; stage_seen_ok <= 1'b0; end
            else state <= FAILED;
          end else count <= count - 1;
        end
        READ_GATE: begin
          if (phy_sample_ok) stage_seen_ok <= 1'b1;
          if (count == 0) begin
            if (stage_seen_ok || phy_sample_ok) begin state <= READ_EYE; count <= READ_EYE_CK; stage_seen_ok <= 1'b0; end
            else state <= FAILED;
          end else count <= count - 1;
        end
        READ_EYE: begin
          if (phy_sample_ok) stage_seen_ok <= 1'b1;
          if (count == 0) begin
            if (stage_seen_ok || phy_sample_ok) state <= COMPLETE;
            else state <= FAILED;
          end else count <= count - 1;
        end
        COMPLETE: if (!start) state <= IDLE;
        FAILED:   if (!start) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
