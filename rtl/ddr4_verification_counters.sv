// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_verification_counters (
  input  logic clk,
  input  logic rst_n,
  input  logic cmd_act,
  input  logic cmd_rd,
  input  logic cmd_wr,
  input  logic cmd_pre,
  input  logic cmd_ref,
  input  logic row_hit,
  input  logic protocol_error,
  output logic [31:0] act_count,
  output logic [31:0] rd_count,
  output logic [31:0] wr_count,
  output logic [31:0] pre_count,
  output logic [31:0] ref_count,
  output logic [31:0] row_hit_count,
  output logic [31:0] error_count
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      act_count <= 0; rd_count <= 0; wr_count <= 0; pre_count <= 0;
      ref_count <= 0; row_hit_count <= 0; error_count <= 0;
    end else begin
      if (cmd_act) act_count <= act_count + 1;
      if (cmd_rd)  rd_count  <= rd_count + 1;
      if (cmd_wr)  wr_count  <= wr_count + 1;
      if (cmd_pre) pre_count <= pre_count + 1;
      if (cmd_ref) ref_count <= ref_count + 1;
      if (row_hit) row_hit_count <= row_hit_count + 1;
      if (protocol_error) error_count <= error_count + 1;
    end
  end
endmodule
