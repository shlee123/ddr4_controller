// SPDX-License-Identifier: MIT
// Icarus-compatible DDR4 behavioral model for CI smoke regression.
// Supports ACT, READ, PRECHARGE and a deterministic BL8 read stream.

`timescale 1ns/1ps

module ddr4_sdram_model #(
  parameter integer DQ_W   = 16,
  parameter integer ADDR_W = 17,
  parameter integer BA_W   = 2,
  parameter integer BG_W   = 2,
  parameter integer CL_CK  = 11,
  parameter integer BL_UI  = 8
)(
  input  wire                   reset_n,
  input  wire                   ck_t,
  input  wire                   ck_c,
  input  wire                   cke,
  input  wire                   cs_n,
  input  wire                   act_n,
  input  wire                   ras_n,
  input  wire                   cas_n,
  input  wire                   we_n,
  input  wire [ADDR_W-1:0]      a,
  input  wire [BA_W-1:0]        ba,
  input  wire [BG_W-1:0]        bg,
  input  wire                   odt,
  inout  wire [DQ_W-1:0]        dq,
  inout  wire [DQ_W/8-1:0]      dqs_t,
  inout  wire [DQ_W/8-1:0]      dqs_c,
  inout  wire [DQ_W/8-1:0]      dm_n,
  output wire                   alert_n
);

  localparam integer NUM_BANKS = 1 << (BG_W + BA_W);
  localparam integer DQS_W = DQ_W / 8;

  reg [14:0] open_row [0:NUM_BANKS-1];
  reg        bank_open [0:NUM_BANKS-1];
  reg [DQ_W-1:0] dq_out;
  reg [DQS_W-1:0] dqs_t_out;
  reg [DQS_W-1:0] dqs_c_out;
  reg dq_oe;

  reg read_pending;
  reg [7:0] read_latency;
  reg [3:0] read_ui;
  reg [15:0] read_seed;

  integer i;
  integer bank_index;

  assign dq      = dq_oe ? dq_out : {DQ_W{1'bz}};
  assign dqs_t   = dq_oe ? dqs_t_out : {DQS_W{1'bz}};
  assign dqs_c   = dq_oe ? dqs_c_out : {DQS_W{1'bz}};
  assign alert_n = 1'b1;

  always @(posedge ck_t or negedge reset_n) begin
    if (!reset_n) begin
      for (i = 0; i < NUM_BANKS; i = i + 1) begin
        open_row[i] <= 15'd0;
        bank_open[i] <= 1'b0;
      end
      dq_out       <= {DQ_W{1'b0}};
      dqs_t_out    <= {DQS_W{1'b0}};
      dqs_c_out    <= {DQS_W{1'b1}};
      dq_oe        <= 1'b0;
      read_pending <= 1'b0;
      read_latency <= 8'd0;
      read_ui      <= 4'd0;
      read_seed    <= 16'd0;
    end else begin
      dq_oe <= 1'b0;

      if (read_pending) begin
        if (read_latency != 0) begin
          read_latency <= read_latency - 1'b1;
        end else begin
          dq_oe     <= 1'b1;
          dq_out    <= read_seed + read_ui;
          dqs_t_out <= {DQS_W{read_ui[0]}};
          dqs_c_out <= {DQS_W{~read_ui[0]}};
          if (read_ui == BL_UI-1) begin
            read_pending <= 1'b0;
            read_ui      <= 4'd0;
          end else begin
            read_ui <= read_ui + 1'b1;
          end
        end
      end

      if (cke && !cs_n) begin
        bank_index = {bg, ba};

        if (!act_n) begin
          bank_open[bank_index] <= 1'b1;
          open_row[bank_index]  <= a[14:0];
        end else begin
          case ({ras_n, cas_n, we_n})
            3'b101: begin // READ
              if (bank_open[bank_index]) begin
                read_seed    <= {open_row[bank_index][7:0], a[7:0]};
                read_latency <= CL_CK;
                read_ui      <= 4'd0;
                read_pending <= 1'b1;
              end
            end

            3'b110: begin // PRECHARGE
              if (a[10]) begin
                for (i = 0; i < NUM_BANKS; i = i + 1)
                  bank_open[i] <= 1'b0;
              end else begin
                bank_open[bank_index] <= 1'b0;
              end
            end

            default: begin end
          endcase
        end
      end
    end
  end

endmodule
