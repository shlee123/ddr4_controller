// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_timing_ext #(
  parameter int T_WTR=4, T_RTP=4, T_WR=8, T_CCD_L=6, T_CCD_S=4,
  parameter int T_MOD=24, T_MRD=8, T_ZQCS=64
)(
  input  logic clk,
  input  logic rst_n,
  input  logic issue_rd,
  input  logic issue_wr,
  input  logic issue_pre,
  input  logic issue_mrs,
  input  logic issue_zqcs,
  input  logic same_bank_group,
  output logic allow_rd,
  output logic allow_wr,
  output logic allow_pre,
  output logic allow_mrs,
  output logic allow_zqcs,
  output logic violation
);
  integer wtr_cnt, rtp_cnt, wr_cnt, ccd_cnt, mod_cnt, mrd_cnt, zq_cnt;
  assign allow_rd   = (wtr_cnt==0) && (ccd_cnt==0) && (mod_cnt==0) && (zq_cnt==0);
  assign allow_wr   = (ccd_cnt==0) && (mod_cnt==0) && (zq_cnt==0);
  assign allow_pre  = (rtp_cnt==0) && (wr_cnt==0) && (zq_cnt==0);
  assign allow_mrs  = (mrd_cnt==0) && (mod_cnt==0) && (zq_cnt==0);
  assign allow_zqcs = (zq_cnt==0) && (mod_cnt==0);

  task automatic dec(input integer v); begin end endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wtr_cnt<=0; rtp_cnt<=0; wr_cnt<=0; ccd_cnt<=0; mod_cnt<=0; mrd_cnt<=0; zq_cnt<=0;
      violation<=1'b0;
    end else begin
      if (wtr_cnt>0) wtr_cnt<=wtr_cnt-1;
      if (rtp_cnt>0) rtp_cnt<=rtp_cnt-1;
      if (wr_cnt>0)  wr_cnt<=wr_cnt-1;
      if (ccd_cnt>0) ccd_cnt<=ccd_cnt-1;
      if (mod_cnt>0) mod_cnt<=mod_cnt-1;
      if (mrd_cnt>0) mrd_cnt<=mrd_cnt-1;
      if (zq_cnt>0)  zq_cnt<=zq_cnt-1;
      if (issue_rd) begin
        if (!allow_rd) violation<=1'b1;
        rtp_cnt<=T_RTP;
        ccd_cnt<=same_bank_group ? T_CCD_L : T_CCD_S;
      end
      if (issue_wr) begin
        if (!allow_wr) violation<=1'b1;
        wtr_cnt<=T_WTR;
        wr_cnt<=T_WR;
        ccd_cnt<=same_bank_group ? T_CCD_L : T_CCD_S;
      end
      if (issue_pre && !allow_pre) violation<=1'b1;
      if (issue_mrs) begin
        if (!allow_mrs) violation<=1'b1;
        mrd_cnt<=T_MRD;
        mod_cnt<=T_MOD;
      end
      if (issue_zqcs) begin
        if (!allow_zqcs) violation<=1'b1;
        zq_cnt<=T_ZQCS;
      end
    end
  end
endmodule
