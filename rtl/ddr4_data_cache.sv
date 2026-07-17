// SPDX-License-Identifier: MIT
// 64-line direct-mapped data cache for the DDR4 controller read/write datapath.

`timescale 1ns/1ps

import ddr4_ctrl_pkg::*;

module ddr4_data_cache #(
  parameter int AXI_ADDR_W  = ddr4_ctrl_pkg::AXI_ADDR_W,
  parameter int AXI_DATA_W  = ddr4_ctrl_pkg::AXI_DATA_W,
  parameter int CACHE_LINES = ddr4_ctrl_pkg::CACHE_LINES,
  parameter int CACHE_IDX_W = $clog2(CACHE_LINES)
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic [AXI_ADDR_W-1:0] lookup_addr,
  output logic                  lookup_hit,
  output logic [AXI_DATA_W-1:0] lookup_data,

  input  logic                  write_valid,
  input  logic [AXI_ADDR_W-1:0] write_addr,
  input  logic [AXI_DATA_W-1:0] write_data,

  input  logic                  invalidate
);

  logic [AXI_DATA_W-1:0] cache_data  [0:CACHE_LINES-1];
  logic [AXI_ADDR_W-1:CACHE_IDX_W+2] cache_tag [0:CACHE_LINES-1];
  logic                  cache_valid [0:CACHE_LINES-1];

  logic [CACHE_IDX_W-1:0] lookup_idx;
  logic [CACHE_IDX_W-1:0] write_idx;
  integer i;

  assign lookup_idx  = lookup_addr[CACHE_IDX_W+1:2];
  assign write_idx   = write_addr[CACHE_IDX_W+1:2];
  assign lookup_hit  = cache_valid[lookup_idx] &&
                       (cache_tag[lookup_idx] == lookup_addr[AXI_ADDR_W-1:CACHE_IDX_W+2]);
  assign lookup_data = cache_data[lookup_idx];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < CACHE_LINES; i = i + 1) begin
        cache_valid[i] <= 1'b0;
        cache_data[i]  <= '0;
        cache_tag[i]   <= '0;
      end
    end else begin
      if (invalidate) begin
        for (i = 0; i < CACHE_LINES; i = i + 1) begin
          cache_valid[i] <= 1'b0;
        end
      end else if (write_valid) begin
        cache_valid[write_idx] <= 1'b1;
        cache_data[write_idx]  <= write_data;
        cache_tag[write_idx]   <= write_addr[AXI_ADDR_W-1:CACHE_IDX_W+2];
      end
    end
  end

endmodule : ddr4_data_cache
