// SPDX-License-Identifier: MIT
// Micron MT40A256M16LY-062E:F protocol-functional simulation model.
// Organization: 256M x 16, BG0, BA[1:0], A[14:0], A[9:0], BL8.
`timescale 1ns/1ps

module ddr4_sdram_model
  import ddr4_ctrl_pkg::*;
#(
  parameter int DQ_W = 16,
  parameter int ADDR_W = DDR_ADDR_W,
  parameter int BA_W = 2,
  parameter int BG_W = DDR_BG_W,
  parameter int BL_UI = 8,
  parameter int CL_CK = 22,
  parameter int CWL_CK = 16,
  parameter int MEM_AW = 20,
  parameter bit STRICT_TIMING = 1'b0,
  parameter int TRCD_CK = 7,
  parameter int TRP_CK = 7,
  parameter int TRAS_CK = 16,
  parameter int TRFC_CK = 130,
  parameter int TMRD_CK = 8
)(
  input logic reset_n, ck_t, ck_c, cke, cs_n, act_n,
  input logic ras_n, cas_n, we_n,
  input logic [ADDR_W-1:0] a,
  input logic [BA_W-1:0] ba,
  input logic [BG_W-1:0] bg,
  input logic odt,
  inout wire [DQ_W-1:0] dq,
  inout wire [DQ_W/8-1:0] dqs_t, dqs_c, dm_n,
  output logic alert_n
);
  localparam int DQS_W = DQ_W/8;
  localparam int NUM_BANKS = 8;
  typedef logic [27:0] mem_key_t;
  localparam int STORE_DEPTH = 1 << MEM_AW;
  logic [DQ_W-1:0] store_data [0:STORE_DEPTH-1];
  mem_key_t store_tag [0:STORE_DEPTH-1];
  logic store_valid [0:STORE_DEPTH-1];
  logic [14:0] open_row [0:NUM_BANKS-1];
  logic bank_open [0:NUM_BANKS-1];
  logic [15:0] mr [0:6];
  integer act_age [0:NUM_BANKS-1];
  integer pre_age [0:NUM_BANKS-1];
  integer refresh_age, mrs_age;

  logic [DQ_W-1:0] dq_drv;
  logic [DQS_W-1:0] dqs_t_drv, dqs_c_drv;
  logic dq_oe, rd_pending, wr_pending, rd_ap, wr_ap;
  integer rd_half_latency, wr_half_latency, rd_ui, wr_ui;
  integer rd_bank, wr_bank;
  mem_key_t rd_base, wr_base;

  assign dq = dq_oe ? dq_drv : 'z;
  assign dqs_t = dq_oe ? dqs_t_drv : 'z;
  assign dqs_c = dq_oe ? dqs_c_drv : 'z;

  function automatic integer bank_idx(input logic ibg0, input logic [1:0] iba);
    bank_idx = {ibg0, iba};
  endfunction
  function automatic mem_key_t logical_addr(
    input logic ibg0, input logic [1:0] iba,
    input logic [14:0] row, input logic [9:0] col);
    logical_addr = {ibg0, iba, row, col};
  endfunction
  task automatic violation(input string msg);
    begin
      alert_n <= 1'b0;
      if (STRICT_TIMING) $error("MT40A256M16LY-062E:F violation: %s", msg);
    end
  endtask

  integer i, bank, mr_index;
  mem_key_t key;
  logic [MEM_AW-1:0] slot;

  always @(posedge ck_t or negedge reset_n) begin
    if (!reset_n) begin
      alert_n <= 1'b1;
      refresh_age <= TRFC_CK;
      mrs_age <= TMRD_CK;
      rd_pending <= 1'b0;
      wr_pending <= 1'b0;
      rd_half_latency <= 0;
      wr_half_latency <= 0;
      rd_ui <= 0;
      wr_ui <= 0;
      for (i=0; i<NUM_BANKS; i=i+1) begin
        bank_open[i] <= 1'b0;
        open_row[i] <= '0;
        act_age[i] <= TRAS_CK;
        pre_age[i] <= TRP_CK;
      end
      for (i=0; i<7; i=i+1) mr[i] <= '0;
      for (i=0; i<STORE_DEPTH; i=i+1) store_valid[i] <= 1'b0;
    end else begin
      if (!alert_n) alert_n <= 1'b1;
      if (refresh_age < TRFC_CK) refresh_age <= refresh_age + 1;
      if (mrs_age < TMRD_CK) mrs_age <= mrs_age + 1;
      for (i=0; i<NUM_BANKS; i=i+1) begin
        if (act_age[i] < TRAS_CK) act_age[i] <= act_age[i] + 1;
        if (pre_age[i] < TRP_CK) pre_age[i] <= pre_age[i] + 1;
      end

      if (cke && !cs_n) begin
        bank = bank_idx(bg[0], ba[1:0]);
        if (BG_W > 1 && bg[1] !== 1'b0)
          violation("BG1 must be LOW/not populated for x16");
        if (!act_n) begin
          if (refresh_age < TRFC_CK) violation("ACT before tRFC");
          if (pre_age[bank] < TRP_CK) violation("ACT before tRP");
          if (bank_open[bank]) violation("ACT to open bank");
          bank_open[bank] <= 1'b1;
          open_row[bank] <= a[14:0];
          act_age[bank] <= 0;
        end else case ({ras_n,cas_n,we_n})
          3'b000: begin // MRS
            mr_index = {bg[0],ba[1:0]};
            if (mrs_age < TMRD_CK) violation("MRS before tMRD");
            if (mr_index <= 6) mr[mr_index] <= a[15:0];
            else violation("reserved MR7");
            mrs_age <= 0;
          end
          3'b001: begin // REF
            for (i=0; i<NUM_BANKS; i=i+1)
              if (bank_open[i]) violation("REF requires precharged banks");
            if (refresh_age < TRFC_CK) violation("REF before tRFC");
            refresh_age <= 0;
          end
          3'b010: begin // PRE/PREA
            if (a[10]) begin
              for (i=0; i<NUM_BANKS; i=i+1) begin
                if (bank_open[i] && act_age[i] < TRAS_CK) violation("PREA before tRAS");
                bank_open[i] <= 1'b0;
                pre_age[i] <= 0;
              end
            end else begin
              if (bank_open[bank] && act_age[bank] < TRAS_CK) violation("PRE before tRAS");
              bank_open[bank] <= 1'b0;
              pre_age[bank] <= 0;
            end
          end
          3'b100: begin // WR/WRA
            if (!bank_open[bank]) violation("WRITE to closed bank");
            if (act_age[bank] < TRCD_CK) violation("WRITE before tRCD");
            wr_base <= logical_addr(bg[0],ba[1:0],open_row[bank],a[9:0]);
            wr_bank <= bank;
            wr_ap <= a[10];
            wr_ui <= 0;
            wr_half_latency <= 2*CWL_CK;
            wr_pending <= 1'b1;
          end
          3'b101: begin // RD/RDA
            if (!bank_open[bank]) violation("READ to closed bank");
            if (act_age[bank] < TRCD_CK) violation("READ before tRCD");
            rd_base <= logical_addr(bg[0],ba[1:0],open_row[bank],a[9:0]);
            rd_bank <= bank;
            rd_ap <= a[10];
            rd_ui <= 0;
            rd_half_latency <= 2*CL_CK;
            rd_pending <= 1'b1;
          end
          3'b110: begin // ZQCL/ZQCS
            for (i=0; i<NUM_BANKS; i=i+1)
              if (bank_open[i]) violation("ZQ requires precharged banks");
          end
          3'b111: begin end // NOP
          default: begin end
        endcase
      end
    end
  end

  // BL8 read transfer on both CK edges (four CK periods).
  always @(ck_t or negedge reset_n) begin
    if (!reset_n) begin
      dq_drv <= '0;
      dqs_t_drv <= '0;
      dqs_c_drv <= '1;
      dq_oe <= 1'b0;
    end else begin
      dq_oe <= 1'b0;
      if (rd_pending) begin
        if (rd_half_latency > 0) rd_half_latency <= rd_half_latency - 1;
        else begin
          key = rd_base + rd_ui;
          slot = key[MEM_AW-1:0];
          dq_drv <= (store_valid[slot] && store_tag[slot] == key)
                    ? store_data[slot] : 'x;
          dqs_t_drv <= {DQS_W{~ck_t}};
          dqs_c_drv <= {DQS_W{ck_t}};
          dq_oe <= 1'b1;
          if (rd_ui == BL_UI-1) begin
            rd_pending <= 1'b0;
            rd_ui <= 0;
            if (rd_ap) begin
              bank_open[rd_bank] <= 1'b0;
              pre_age[rd_bank] <= 0;
            end
          end else rd_ui <= rd_ui + 1;
        end
      end
      if (wr_pending && wr_half_latency > 0)
        wr_half_latency <= wr_half_latency - 1;
    end
  end

  // Write data is captured on both edges of incoming DQS, with per-byte DM.
  always @(dqs_t[0] or negedge reset_n) begin
    integer lane;
    if (!reset_n) wr_ui <= 0;
    else if (wr_pending && wr_half_latency == 0 &&
             (dqs_t[0] === 1'b0 || dqs_t[0] === 1'b1)) begin
      key = wr_base + wr_ui;
      slot = key[MEM_AW-1:0];
      if (!store_valid[slot] || store_tag[slot] != key)
        store_data[slot] = 'x;
      store_tag[slot] = key;
      store_valid[slot] = 1'b1;
      for (lane=0; lane<DQS_W; lane=lane+1)
        if (dm_n[lane] === 1'b0)
          store_data[slot][8*lane +: 8] = dq[8*lane +: 8];
      if (wr_ui == BL_UI-1) begin
        wr_pending <= 1'b0;
        wr_ui <= 0;
        if (wr_ap) begin
          bank_open[wr_bank] <= 1'b0;
          pre_age[wr_bank] <= 0;
        end
      end else wr_ui <= wr_ui + 1;
    end
  end
endmodule
