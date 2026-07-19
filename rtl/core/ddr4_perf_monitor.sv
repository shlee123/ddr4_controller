// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_perf_monitor #(
  parameter int QUEUE_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic req_accept,
  input  logic rsp_complete,
  input  logic cmd_rd,
  input  logic cmd_wr,
  input  logic cmd_ref,
  input  logic row_hit,
  input  logic [QUEUE_W-1:0] queue_level,
  output logic [31:0] cycles,
  output logic [31:0] busy_cycles,
  output logic [31:0] read_count,
  output logic [31:0] write_count,
  output logic [31:0] refresh_count,
  output logic [31:0] row_hit_count,
  output logic [31:0] latency_sum,
  output logic [31:0] max_queue_level
);
  logic [31:0] inflight_age;
  logic inflight;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycles <= 0; busy_cycles <= 0; read_count <= 0; write_count <= 0;
      refresh_count <= 0; row_hit_count <= 0; latency_sum <= 0;
      max_queue_level <= 0; inflight_age <= 0; inflight <= 0;
    end else begin
      cycles <= cycles + 1'b1;
      if (cmd_rd || cmd_wr || cmd_ref) busy_cycles <= busy_cycles + 1'b1;
      if (cmd_rd) read_count <= read_count + 1'b1;
      if (cmd_wr) write_count <= write_count + 1'b1;
      if (cmd_ref) refresh_count <= refresh_count + 1'b1;
      if (row_hit) row_hit_count <= row_hit_count + 1'b1;
      if (queue_level > max_queue_level) max_queue_level <= queue_level;
      if (req_accept && !inflight) begin inflight <= 1'b1; inflight_age <= 0; end
      else if (inflight) inflight_age <= inflight_age + 1'b1;
      if (rsp_complete && inflight) begin
        latency_sum <= latency_sum + inflight_age + 1'b1;
        inflight <= 1'b0;
      end
    end
  end
endmodule
