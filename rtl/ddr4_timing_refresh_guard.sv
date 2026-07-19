// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_timing_refresh_guard #(
  parameter int T_REFI_CK = 128,
  parameter int T_RFC_CK  = 24,
  parameter int T_RCD_CK  = 8,
  parameter int T_RP_CK   = 8,
  parameter int T_RAS_CK  = 18,
  parameter int T_RC_CK   = 26,
  parameter int T_CCD_CK  = 4,
  parameter int T_RRD_CK  = 4,
  parameter int T_FAW_CK  = 16,
  parameter int BANKS     = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic refresh_ack,
  input  logic issue_act,
  input  logic issue_pre,
  input  logic issue_rd,
  input  logic issue_wr,
  input  logic [$clog2(BANKS)-1:0] issue_bank,
  output logic refresh_pending,
  output logic refresh_block,
  output logic allow_act,
  output logic allow_pre,
  output logic allow_col,
  output logic violation
);
  integer i;
  logic [$clog2(T_REFI_CK+1)-1:0] refi_cnt;
  logic [$clog2(T_RFC_CK+1)-1:0]  rfc_cnt;
  logic [$clog2(T_CCD_CK+1)-1:0]  ccd_cnt;
  logic [$clog2(T_RRD_CK+1)-1:0]  rrd_cnt;
  logic [$clog2(T_FAW_CK+1)-1:0]  act_age [0:3];
  logic [2:0] act_count;
  logic [$clog2(T_RCD_CK+1)-1:0] rcd_cnt [0:BANKS-1];
  logic [$clog2(T_RP_CK+1)-1:0]  rp_cnt  [0:BANKS-1];
  logic [$clog2(T_RAS_CK+1)-1:0] ras_cnt [0:BANKS-1];
  logic [$clog2(T_RC_CK+1)-1:0]  rc_cnt  [0:BANKS-1];

  always_comb begin
    act_count = 0;
    for (i = 0; i < 4; i = i + 1)
      if (act_age[i] != 0) act_count = act_count + 1'b1;
  end

  assign refresh_block = (rfc_cnt != 0);
  assign allow_act = !refresh_pending && !refresh_block &&
                     (rrd_cnt == 0) && (act_count < 4) &&
                     (rp_cnt[issue_bank] == 0) && (rc_cnt[issue_bank] == 0);
  assign allow_pre = !refresh_pending && !refresh_block &&
                     (ras_cnt[issue_bank] == 0);
  assign allow_col = !refresh_pending && !refresh_block &&
                     (rcd_cnt[issue_bank] == 0) && (ccd_cnt == 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      refi_cnt        <= T_REFI_CK-1;
      rfc_cnt         <= '0;
      ccd_cnt         <= '0;
      rrd_cnt         <= '0;
      refresh_pending <= 1'b0;
      violation       <= 1'b0;
      for (i = 0; i < BANKS; i = i + 1) begin
        rcd_cnt[i] <= '0;
        rp_cnt[i]  <= '0;
        ras_cnt[i] <= '0;
        rc_cnt[i]  <= '0;
      end
      for (i = 0; i < 4; i = i + 1) act_age[i] <= '0;
    end else begin
      if (refi_cnt == 0) begin
        refresh_pending <= 1'b1;
        refi_cnt <= T_REFI_CK-1;
      end else begin
        refi_cnt <= refi_cnt - 1'b1;
      end

      if (refresh_ack) begin
        refresh_pending <= 1'b0;
        rfc_cnt <= T_RFC_CK;
      end else if (rfc_cnt != 0) begin
        rfc_cnt <= rfc_cnt - 1'b1;
      end

      if (ccd_cnt != 0) ccd_cnt <= ccd_cnt - 1'b1;
      if (rrd_cnt != 0) rrd_cnt <= rrd_cnt - 1'b1;
      for (i = 0; i < BANKS; i = i + 1) begin
        if (rcd_cnt[i] != 0) rcd_cnt[i] <= rcd_cnt[i] - 1'b1;
        if (rp_cnt[i]  != 0) rp_cnt[i]  <= rp_cnt[i]  - 1'b1;
        if (ras_cnt[i] != 0) ras_cnt[i] <= ras_cnt[i] - 1'b1;
        if (rc_cnt[i]  != 0) rc_cnt[i]  <= rc_cnt[i]  - 1'b1;
      end
      for (i = 0; i < 4; i = i + 1)
        if (act_age[i] != 0) act_age[i] <= act_age[i] - 1'b1;

      if (issue_act) begin
        if (!allow_act) violation <= 1'b1;
        rcd_cnt[issue_bank] <= T_RCD_CK;
        ras_cnt[issue_bank] <= T_RAS_CK;
        rc_cnt[issue_bank]  <= T_RC_CK;
        rrd_cnt <= T_RRD_CK;
        if (act_age[0] == 0) act_age[0] <= T_FAW_CK;
        else if (act_age[1] == 0) act_age[1] <= T_FAW_CK;
        else if (act_age[2] == 0) act_age[2] <= T_FAW_CK;
        else if (act_age[3] == 0) act_age[3] <= T_FAW_CK;
      end
      if (issue_pre) begin
        if (!allow_pre) violation <= 1'b1;
        rp_cnt[issue_bank] <= T_RP_CK;
      end
      if (issue_rd || issue_wr) begin
        if (!allow_col) violation <= 1'b1;
        ccd_cnt <= T_CCD_CK;
      end
    end
  end
endmodule
