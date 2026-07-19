// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module tb_ddr4_controller_m10;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic refresh_ack, issue_act, issue_pre, issue_rd, issue_wr;
  logic [3:0] issue_bank;
  logic refresh_pending, refresh_block, allow_act, allow_pre, allow_col, violation;

  ddr4_timing_refresh_guard #(
    .T_REFI_CK(32), .T_RFC_CK(6), .T_RCD_CK(3), .T_RP_CK(3),
    .T_RAS_CK(5), .T_RC_CK(8), .T_CCD_CK(2), .T_RRD_CK(2), .T_FAW_CK(8), .BANKS(16)
  ) u_guard (
    .clk, .rst_n, .refresh_ack, .issue_act, .issue_pre, .issue_rd, .issue_wr,
    .issue_bank, .refresh_pending, .refresh_block, .allow_act, .allow_pre, .allow_col, .violation
  );

  logic [3:0] req_valid, req_write;
  logic [3:0] req_bank [0:3];
  logic [14:0] req_row [0:3];
  logic [15:0] open_valid;
  logic [14:0] open_row [0:15];
  logic grant_accept, grant_valid, grant_row_hit, grant_write;
  logic [1:0] grant_index;

  ddr4_bank_scheduler #(.ENTRIES(4), .AGE_W(4), .BANK_W(4), .ROW_W(15)) u_sched (
    .clk, .rst_n, .req_valid, .req_write, .req_bank, .req_row,
    .open_valid, .open_row, .grant_accept, .grant_valid, .grant_index,
    .grant_row_hit, .grant_write
  );

  logic train_start, phy_sample_ok;
  logic train_busy, train_done, train_fail, write_level_en, read_gate_en, read_eye_en;
  logic [2:0] train_phase;
  ddr4_phy_training #(.RESET_CK(2), .WRITE_LEVEL_CK(3), .READ_GATE_CK(3), .READ_EYE_CK(3)) u_train (
    .clk, .rst_n, .start(train_start), .phy_sample_ok, .busy(train_busy), .done(train_done),
    .fail(train_fail), .write_level_en, .read_gate_en, .read_eye_en, .phase(train_phase)
  );

  logic [31:0] act_count, rd_count, wr_count, pre_count, ref_count, row_hit_count, error_count;
  ddr4_verification_counters u_count (
    .clk, .rst_n, .cmd_act(issue_act), .cmd_rd(issue_rd), .cmd_wr(issue_wr),
    .cmd_pre(issue_pre), .cmd_ref(refresh_ack), .row_hit(grant_valid && grant_accept && grant_row_hit),
    .protocol_error(violation), .act_count, .rd_count, .wr_count, .pre_count,
    .ref_count, .row_hit_count, .error_count
  );

  task automatic pulse_act(input logic [3:0] bank);
    begin
      issue_bank = bank;
      while (!allow_act) @(posedge clk);
      issue_act = 1;
      @(posedge clk);
      #1 issue_act = 0;
    end
  endtask

  task automatic pulse_col(input logic wr, input logic [3:0] bank);
    begin
      issue_bank = bank;
      while (!allow_col) @(posedge clk);
      issue_rd = !wr;
      issue_wr = wr;
      @(posedge clk);
      #1 issue_rd = 0;
      issue_wr = 0;
    end
  endtask

  task automatic pulse_pre(input logic [3:0] bank);
    begin
      issue_bank = bank;
      while (!allow_pre) @(posedge clk);
      issue_pre = 1;
      @(posedge clk);
      #1 issue_pre = 0;
    end
  endtask

  integer i;
  initial begin
    refresh_ack = 0; issue_act = 0; issue_pre = 0; issue_rd = 0; issue_wr = 0; issue_bank = 0;
    req_valid = 0; req_write = 0; open_valid = 0; grant_accept = 0;
    train_start = 0; phy_sample_ok = 0;
    for (i = 0; i < 4; i = i + 1) begin req_bank[i] = i; req_row[i] = 0; end
    for (i = 0; i < 16; i = i + 1) open_row[i] = 0;

    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    pulse_act(0);
    pulse_col(0, 0);
    pulse_pre(0);
    wait (refresh_pending);
    refresh_ack = 1;
    @(posedge clk);
    #1 refresh_ack = 0;
    if (!refresh_block) $fatal(1, "M7 refresh did not enter tRFC block");
    while (refresh_block) @(posedge clk);
    if (violation) $fatal(1, "M7 legal sequence reported timing violation");

    open_valid[2] = 1;
    open_row[2] = 15'h123;
    req_valid = 4'b0011;
    req_bank[0] = 1; req_row[0] = 15'h001;
    req_bank[1] = 2; req_row[1] = 15'h123;
    repeat (2) @(posedge clk);
    if (!grant_valid || grant_index != 1 || !grant_row_hit)
      $fatal(1, "M8 row-hit priority failed: grant=%0d hit=%0b", grant_index, grant_row_hit);
    grant_accept = 1;
    @(posedge clk);
    #1 req_valid[1] = 0;
    grant_accept = 0;
    repeat (3) @(posedge clk);
    if (!grant_valid || grant_index != 0)
      $fatal(1, "M8 fairness/age selection failed: grant=%0d", grant_index);
    grant_accept = 1;
    @(posedge clk);
    #1 req_valid = 0;
    grant_accept = 0;

    train_start = 1;
    while (!write_level_en) @(posedge clk);
    phy_sample_ok = 1; @(posedge clk); #1 phy_sample_ok = 0;
    while (!read_gate_en) @(posedge clk);
    phy_sample_ok = 1; @(posedge clk); #1 phy_sample_ok = 0;
    while (!read_eye_en) @(posedge clk);
    phy_sample_ok = 1; @(posedge clk); #1 phy_sample_ok = 0;
    wait (train_done || train_fail);
    if (!train_done || train_fail) $fatal(1, "M9 PHY training did not complete");
    train_start = 0;
    @(posedge clk);

    if (act_count < 1 || rd_count < 1 || pre_count < 1 || ref_count < 1)
      $fatal(1, "M10 command coverage counters incomplete");
    if (row_hit_count < 1) $fatal(1, "M10 row-hit coverage missing");
    if (error_count != 0) $fatal(1, "M10 protocol error counter non-zero: %0d", error_count);

    $display("PASS M7 DDR4 timing and refresh");
    $display("PASS M8 bank-aware scheduler");
    $display("PASS M9 PHY training");
    $display("PASS M10 verification closure");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "M10 regression timeout");
  end
endmodule
