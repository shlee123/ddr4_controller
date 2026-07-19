// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

import ddr4_ctrl_pkg::*;

// Native DDR-clock-domain arbitration layer placed between the AXI CDC
// request FIFOs and the command scheduler. Packed-vector ports keep the
// boundary compatible with Icarus, VCS and synthesis tools; internally the
// vectors map bit-for-bit to ddr_req_t.
module ddr4_native_request_mux #(
  parameter int AXI_ADDR_W = 32,
  parameter int BANK_W = 4,
  parameter int ROW_W = 15,
  parameter int REQ_W = $bits(ddr_req_t)
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic [REQ_W-1:0]     wr_req_in,
  input  logic                 wr_empty_in,
  output logic                 wr_pop,
  output logic [REQ_W-1:0]     wr_req_out,
  output logic                 wr_empty_out,
  input  logic [REQ_W-1:0]     rd_req_in,
  input  logic                 rd_empty_in,
  output logic                 rd_pop,
  output logic [REQ_W-1:0]     rd_req_out,
  output logic                 rd_empty_out,
  input  logic                 downstream_wr_pop,
  input  logic                 downstream_rd_pop,
  output logic                 grant_valid,
  output logic                 grant_write,
  output logic                 grant_row_hit,
  output logic                 timing_violation
);
  ddr_req_t wr_req_s, rd_req_s;
  logic [1:0] req_valid, req_write;
  logic [BANK_W-1:0] req_bank [0:1];
  logic [ROW_W-1:0] req_row [0:1];
  logic [(1<<BANK_W)-1:0] open_valid;
  logic [ROW_W-1:0] open_row [0:(1<<BANK_W)-1];
  logic grant_accept;
  logic [0:0] grant_index;
  logic [BANK_W-1:0] grant_bank;
  logic prefer_writes;
  logic allow_rd, allow_wr, allow_pre, allow_mrs, allow_zq;
  integer i;

  always_comb begin
    wr_req_s = wr_req_in;
    rd_req_s = rd_req_in;
    req_valid[0] = !wr_empty_in;
    req_valid[1] = !rd_empty_in;
    req_write = 2'b01;
    req_bank[0] = wr_req_s.addr[5 +: BANK_W];
    req_bank[1] = rd_req_s.addr[5 +: BANK_W];
    req_row[0] = wr_req_s.addr[9 +: ROW_W];
    req_row[1] = rd_req_s.addr[9 +: ROW_W];
    prefer_writes = !wr_empty_in;

    wr_req_out = wr_req_in;
    rd_req_out = rd_req_in;
    wr_empty_out = 1'b1;
    rd_empty_out = 1'b1;
    if (grant_valid && grant_write && allow_wr)
      wr_empty_out = 1'b0;
    if (grant_valid && !grant_write && allow_rd)
      rd_empty_out = 1'b0;
  end

  assign grant_accept = (grant_write && downstream_wr_pop && !wr_empty_out) ||
                        (!grant_write && downstream_rd_pop && !rd_empty_out);
  assign wr_pop = grant_accept && grant_write;
  assign rd_pop = grant_accept && !grant_write;

  ddr4_scheduler_v2 #(.ENTRIES(2), .BANK_W(BANK_W), .ROW_W(ROW_W), .AGE_W(8)) u_native_sched (
    .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_write(req_write),
    .req_bank(req_bank), .req_row(req_row), .open_valid(open_valid),
    .open_row(open_row), .prefer_writes(prefer_writes),
    .grant_accept(grant_accept), .grant_valid(grant_valid),
    .grant_index(grant_index), .grant_row_hit(grant_row_hit),
    .grant_write(grant_write), .grant_bank(grant_bank));

  ddr4_timing_ext #(.T_WTR(2), .T_RTP(2), .T_WR(3), .T_CCD_L(3),
                    .T_CCD_S(2), .T_MOD(4), .T_MRD(2), .T_ZQCS(5)) u_native_timing (
    .clk(clk), .rst_n(rst_n),
    .issue_rd(grant_accept && !grant_write),
    .issue_wr(grant_accept && grant_write),
    .issue_pre(1'b0), .issue_mrs(1'b0), .issue_zqcs(1'b0),
    .same_bank_group(req_bank[0][BANK_W-1] == req_bank[1][BANK_W-1]),
    .allow_rd(allow_rd), .allow_wr(allow_wr), .allow_pre(allow_pre),
    .allow_mrs(allow_mrs), .allow_zqcs(allow_zq),
    .violation(timing_violation));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      open_valid <= '0;
      for (i=0; i<(1<<BANK_W); i=i+1) open_row[i] <= '0;
    end else if (grant_accept) begin
      open_valid[grant_bank] <= 1'b1;
      open_row[grant_bank] <= grant_write ? req_row[0] : req_row[1];
    end
  end
endmodule
