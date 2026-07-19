// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_bank_scheduler #(
  parameter int ENTRIES = 4,
  parameter int AGE_W   = 8,
  parameter int BANK_W  = 4,
  parameter int ROW_W   = 15
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ENTRIES-1:0] req_valid,
  input  logic [ENTRIES-1:0] req_write,
  input  logic [BANK_W-1:0] req_bank [0:ENTRIES-1],
  input  logic [ROW_W-1:0]  req_row  [0:ENTRIES-1],
  input  logic [(1<<BANK_W)-1:0] open_valid,
  input  logic [ROW_W-1:0] open_row [0:(1<<BANK_W)-1],
  input  logic grant_accept,
  output logic grant_valid,
  output logic [$clog2(ENTRIES)-1:0] grant_index,
  output logic grant_row_hit,
  output logic grant_write
);
  localparam int IW = (ENTRIES <= 2) ? 1 : $clog2(ENTRIES);
  integer i;
  logic [AGE_W-1:0] age [0:ENTRIES-1];
  logic hit;
  logic [AGE_W-1:0] best_age;

  always_comb begin
    grant_valid   = 1'b0;
    grant_index   = '0;
    grant_row_hit = 1'b0;
    grant_write   = 1'b0;
    best_age      = '0;

    // First-ready policy: row hits first; age resolves ties and prevents starvation.
    for (i = 0; i < ENTRIES; i = i + 1) begin
      hit = open_valid[req_bank[i]] && (open_row[req_bank[i]] == req_row[i]);
      if (req_valid[i]) begin
        if (!grant_valid ||
            (hit && !grant_row_hit) ||
            ((hit == grant_row_hit) && (age[i] > best_age))) begin
          grant_valid   = 1'b1;
          grant_index   = IW'(i);
          grant_row_hit = hit;
          grant_write   = req_write[i];
          best_age      = age[i];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < ENTRIES; i = i + 1) age[i] <= '0;
    end else begin
      for (i = 0; i < ENTRIES; i = i + 1) begin
        if (!req_valid[i] || (grant_accept && grant_valid && grant_index == IW'(i)))
          age[i] <= '0;
        else if (&age[i])
          age[i] <= age[i];
        else
          age[i] <= age[i] + 1'b1;
      end
    end
  end
endmodule
