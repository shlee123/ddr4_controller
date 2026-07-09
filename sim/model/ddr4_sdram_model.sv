// SPDX-License-Identifier: MIT
// Micron 4Gb DDR4 SDRAM behavioral command model, first verification version.
// Scope: command decode, bank state, MRS storage, basic ACT/RD/WR/PRE/REF timing checks.
// Not yet modeling analog IO, DQS phasing, training, DBI, CRC, parity, or full data bursts.

`timescale 1ns/1ps

import ddr4_ctrl_pkg::*;

module ddr4_sdram_model #(
  parameter int ROW_W  = DDR_ROW_W,
  parameter int COL_W  = DDR_COL_W,
  parameter int BANK_W = DDR_BANK_W,
  parameter int BG_W   = DDR_BG_W,
  parameter int DQ_W   = DDR_DQ_W,
  parameter bit X16_MODE = 1'b1,

  parameter int T_RCD = T_RCD_CK,
  parameter int T_RP  = T_RP_CK,
  parameter int T_RAS = T_RAS_CK,
  parameter int T_RC  = T_RC_CK,
  parameter int T_MRD = T_MRD_CK,
  parameter int T_MOD = T_MOD_CK
)(
  input  logic                 ck_t,
  input  logic                 ck_c,
  input  logic                 reset_n,
  input  logic                 cke,
  input  logic                 cs_n,
  input  logic                 act_n,
  input  logic                 ras_n,
  input  logic                 cas_n,
  input  logic                 we_n,
  input  logic [BG_W-1:0]      bg,
  input  logic [BANK_W-1:0]    ba,
  input  logic [16:0]          a,
  input  logic                 odt,
  input  logic                 par,
  output logic                 alert_n,
  inout  wire  [DQ_W-1:0]      dq,
  inout  wire  [DQ_W/8-1:0]    dqs_t,
  inout  wire  [DQ_W/8-1:0]    dqs_c,
  inout  wire  [DQ_W/8-1:0]    dm_n
);

  localparam int NUM_BG    = X16_MODE ? 2 : (1 << BG_W);
  localparam int NUM_BANK  = 1 << BANK_W;
  localparam int NUM_BANKS = NUM_BG * NUM_BANK;

  typedef struct packed {
    logic                open;
    logic [ROW_W-1:0]    row;
    int                  act_cycle;
    int                  pre_cycle;
    int                  rdwr_cycle;
  } bank_state_t;

  bank_state_t bank_state [NUM_BANKS];
  logic [16:0] mr [0:6];
  int cycle_count;
  int last_mrs_cycle;
  int last_non_des_cycle;
  logic initialized;

  assign alert_n = 1'b1;
  assign dq      = 'z;
  assign dqs_t   = 'z;
  assign dqs_c   = 'z;
  assign dm_n    = 'z;

  function automatic int bank_index(input logic [BG_W-1:0] f_bg, input logic [BANK_W-1:0] f_ba);
    int bg_i;
    begin
      bg_i = X16_MODE ? int'(f_bg[0]) : int'(f_bg);
      bank_index = (bg_i * NUM_BANK) + int'(f_ba);
    end
  endfunction

  function automatic ddr_cmd_e decode_cmd;
    begin
      if (!cke) begin
        decode_cmd = DDR_CMD_PDE;
      end else if (cs_n) begin
        decode_cmd = DDR_CMD_DES;
      end else if (!act_n) begin
        decode_cmd = DDR_CMD_ACT;
      end else begin
        unique case ({ras_n, cas_n, we_n})
          3'b111: decode_cmd = DDR_CMD_NOP;
          3'b110: decode_cmd = a[10] ? DDR_CMD_PREA : DDR_CMD_PRE;
          3'b101: decode_cmd = a[10] ? DDR_CMD_RDA  : DDR_CMD_RD;
          3'b100: decode_cmd = a[10] ? DDR_CMD_WRA  : DDR_CMD_WR;
          3'b011: decode_cmd = DDR_CMD_MRS;
          3'b010: decode_cmd = DDR_CMD_REF;
          3'b001: decode_cmd = a[10] ? DDR_CMD_ZQCL : DDR_CMD_ZQCS;
          default: decode_cmd = DDR_CMD_UNK;
        endcase
      end
    end
  endfunction

  task automatic timing_error(input string msg);
    begin
      $error("%0t DDR4_MODEL timing/protocol error: %s", $time, msg);
    end
  endtask

  task automatic do_activate(input int idx);
    begin
      if (bank_state[idx].open) begin
        timing_error($sformatf("ACT to open bank index %0d", idx));
      end
      if ((cycle_count - bank_state[idx].pre_cycle) < T_RP) begin
        timing_error($sformatf("tRP violation before ACT bank index %0d", idx));
      end
      if ((cycle_count - bank_state[idx].act_cycle) < T_RC) begin
        timing_error($sformatf("tRC violation before ACT bank index %0d", idx));
      end
      bank_state[idx].open      = 1'b1;
      bank_state[idx].row       = a[ROW_W-1:0];
      bank_state[idx].act_cycle = cycle_count;
    end
  endtask

  task automatic do_read_write(input int idx, input bit is_write, input bit auto_precharge);
    begin
      if (!bank_state[idx].open) begin
        timing_error($sformatf("%s to closed bank index %0d", is_write ? "WRITE" : "READ", idx));
      end
      if ((cycle_count - bank_state[idx].act_cycle) < T_RCD) begin
        timing_error($sformatf("tRCD violation before %s bank index %0d", is_write ? "WRITE" : "READ", idx));
      end
      bank_state[idx].rdwr_cycle = cycle_count;
      if (auto_precharge) begin
        if ((cycle_count - bank_state[idx].act_cycle) < T_RAS) begin
          timing_error($sformatf("tRAS violation before auto-precharge bank index %0d", idx));
        end
        bank_state[idx].open      = 1'b0;
        bank_state[idx].pre_cycle = cycle_count;
      end
    end
  endtask

  task automatic do_precharge(input int idx);
    begin
      if (bank_state[idx].open) begin
        if ((cycle_count - bank_state[idx].act_cycle) < T_RAS) begin
          timing_error($sformatf("tRAS violation before PRE bank index %0d", idx));
        end
      end
      bank_state[idx].open      = 1'b0;
      bank_state[idx].pre_cycle = cycle_count;
    end
  endtask

  task automatic do_precharge_all;
    int i;
    begin
      for (i = 0; i < NUM_BANKS; i++) begin
        do_precharge(i);
      end
    end
  endtask

  task automatic do_refresh;
    int i;
    begin
      for (i = 0; i < NUM_BANKS; i++) begin
        if (bank_state[i].open) begin
          timing_error($sformatf("REF while bank index %0d is active", i));
        end
      end
    end
  endtask

  task automatic do_mrs;
    int mr_idx;
    begin
      mr_idx = {int'(bg[0]), int'(ba)};
      if (mr_idx <= 6) begin
        mr[mr_idx] = a;
      end
      if ((cycle_count - last_mrs_cycle) < T_MRD) begin
        timing_error("tMRD violation between MRS commands");
      end
      last_mrs_cycle = cycle_count;
    end
  endtask

  integer bi;
  initial begin
    cycle_count        = 0;
    last_mrs_cycle     = -1000000;
    last_non_des_cycle = -1000000;
    initialized        = 1'b0;
    for (bi = 0; bi < NUM_BANKS; bi++) begin
      bank_state[bi].open       = 1'b0;
      bank_state[bi].row        = '0;
      bank_state[bi].act_cycle  = -1000000;
      bank_state[bi].pre_cycle  = -1000000;
      bank_state[bi].rdwr_cycle = -1000000;
    end
    for (bi = 0; bi < 7; bi++) mr[bi] = '0;
    $display("DDR4 SDRAM command model loaded: 4Gb %s, BG=%0d, BA=%0d, ROW=%0d, COL=%0d, DQ=%0d",
             X16_MODE ? "x16" : "x8", NUM_BG, NUM_BANK, ROW_W, COL_W, DQ_W);
  end

  always_ff @(negedge reset_n) begin
    initialized <= 1'b0;
    for (int i = 0; i < NUM_BANKS; i++) begin
      bank_state[i].open <= 1'b0;
    end
  end

  always_ff @(posedge ck_t) begin
    ddr_cmd_e cmd;
    int idx;

    cycle_count <= cycle_count + 1;

    if (!reset_n) begin
      initialized <= 1'b0;
    end else begin
      cmd = decode_cmd();
      idx = bank_index(bg, ba);

      unique case (cmd)
        DDR_CMD_DES,
        DDR_CMD_NOP: begin
          // no operation
        end

        DDR_CMD_ACT: begin
          do_activate(idx);
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_RD: begin
          do_read_write(idx, 1'b0, 1'b0);
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_RDA: begin
          do_read_write(idx, 1'b0, 1'b1);
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_WR: begin
          do_read_write(idx, 1'b1, 1'b0);
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_WRA: begin
          do_read_write(idx, 1'b1, 1'b1);
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_PRE: begin
          do_precharge(idx);
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_PREA: begin
          do_precharge_all();
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_REF: begin
          do_refresh();
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_MRS: begin
          do_mrs();
          last_non_des_cycle <= cycle_count;
        end

        DDR_CMD_ZQCL,
        DDR_CMD_ZQCS: begin
          initialized <= 1'b1;
          last_non_des_cycle <= cycle_count;
        end

        default: begin
          timing_error($sformatf("unsupported/unknown command encoding: act_n=%0b ras_n=%0b cas_n=%0b we_n=%0b", act_n, ras_n, cas_n, we_n));
        end
      endcase
    end
  end

endmodule : ddr4_sdram_model
