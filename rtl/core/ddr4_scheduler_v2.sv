// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_scheduler_v2 #(
  parameter int ENTRIES = 8,
  parameter int BANK_W = 4,
  parameter int ROW_W = 15,
  parameter int AGE_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ENTRIES-1:0] req_valid,
  input  logic [ENTRIES-1:0] req_write,
  input  logic [BANK_W-1:0] req_bank [0:ENTRIES-1],
  input  logic [ROW_W-1:0] req_row [0:ENTRIES-1],
  input  logic [(1<<BANK_W)-1:0] open_valid,
  input  logic [ROW_W-1:0] open_row [0:(1<<BANK_W)-1],
  input  logic prefer_writes,
  input  logic grant_accept,
  output logic grant_valid,
  output logic [$clog2(ENTRIES)-1:0] grant_index,
  output logic grant_row_hit,
  output logic grant_write,
  output logic [BANK_W-1:0] grant_bank
);
  integer i;
  logic [AGE_W-1:0] age [0:ENTRIES-1];
  logic found;
  logic candidate_hit;

  always_comb begin
    grant_valid = 1'b0;
    grant_index = '0;
    grant_row_hit = 1'b0;
    grant_write = 1'b0;
    grant_bank = '0;
    found = 1'b0;

    // FR-FCFS: row-hit first, then preferred direction, then oldest.
    for (i = 0; i < ENTRIES; i = i + 1) begin
      candidate_hit = open_valid[req_bank[i]] && (open_row[req_bank[i]] == req_row[i]);
      if (req_valid[i] && candidate_hit && !found && (req_write[i] == prefer_writes)) begin
        grant_valid = 1'b1; grant_index = i; grant_row_hit = 1'b1;
        grant_write = req_write[i]; grant_bank = req_bank[i]; found = 1'b1;
      end
    end
    for (i = 0; i < ENTRIES; i = i + 1) begin
      candidate_hit = open_valid[req_bank[i]] && (open_row[req_bank[i]] == req_row[i]);
      if (req_valid[i] && candidate_hit && !found) begin
        grant_valid = 1'b1; grant_index = i; grant_row_hit = 1'b1;
        grant_write = req_write[i]; grant_bank = req_bank[i]; found = 1'b1;
      end
    end
    for (i = 0; i < ENTRIES; i = i + 1) begin
      if (req_valid[i] && !found && (req_write[i] == prefer_writes)) begin
        grant_valid = 1'b1; grant_index = i; grant_row_hit = 1'b0;
        grant_write = req_write[i]; grant_bank = req_bank[i]; found = 1'b1;
      end
    end
    for (i = 0; i < ENTRIES; i = i + 1) begin
      if (req_valid[i] && !found) begin
        grant_valid = 1'b1; grant_index = i; grant_row_hit = 1'b0;
        grant_write = req_write[i]; grant_bank = req_bank[i]; found = 1'b1;
      end
    end

    // Starvation override: any saturated age wins.
    for (i = 0; i < ENTRIES; i = i + 1) begin
      if (req_valid[i] && (&age[i])) begin
        grant_valid = 1'b1; grant_index = i;
        grant_row_hit = open_valid[req_bank[i]] && (open_row[req_bank[i]] == req_row[i]);
        grant_write = req_write[i]; grant_bank = req_bank[i];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < ENTRIES; i = i + 1) age[i] <= '0;
    end else begin
      for (i = 0; i < ENTRIES; i = i + 1) begin
        if (!req_valid[i] || (grant_accept && grant_valid && grant_index == i)) age[i] <= '0;
        else if (!(&age[i])) age[i] <= age[i] + 1'b1;
      end
    end
  end
endmodule
