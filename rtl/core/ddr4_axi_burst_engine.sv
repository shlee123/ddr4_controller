// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_axi_burst_engine #(
  parameter int ADDR_W = 32
)(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              start,
  input  logic [ADDR_W-1:0] start_addr,
  input  logic [7:0]        burst_len,
  input  logic [2:0]        burst_size,
  input  logic [1:0]        burst_type,
  input  logic              beat_accept,
  output logic              active,
  output logic [ADDR_W-1:0] beat_addr,
  output logic [7:0]        beat_index,
  output logic              beat_last,
  output logic              unsupported
);
  logic [ADDR_W-1:0] base_addr;
  logic [ADDR_W-1:0] bytes_per_beat;
  logic [ADDR_W-1:0] wrap_bytes;
  logic [ADDR_W-1:0] wrap_base;
  logic [ADDR_W-1:0] next_addr;

  always_comb begin
    bytes_per_beat = {{(ADDR_W-4){1'b0}}, 1'b1, 3'b000} >> (3'd3 - burst_size);
    wrap_bytes = bytes_per_beat * (burst_len + 1'b1);
    wrap_base = (wrap_bytes != 0) ? ((base_addr / wrap_bytes) * wrap_bytes) : base_addr;
    next_addr = beat_addr;
    unique case (burst_type)
      2'b00: next_addr = beat_addr;
      2'b01: next_addr = beat_addr + bytes_per_beat;
      2'b10: begin
        next_addr = beat_addr + bytes_per_beat;
        if (next_addr >= wrap_base + wrap_bytes) next_addr = wrap_base;
      end
      default: next_addr = beat_addr;
    endcase
  end

  assign beat_last = active && (beat_index == burst_len);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active      <= 1'b0;
      beat_addr   <= '0;
      beat_index  <= '0;
      base_addr   <= '0;
      unsupported <= 1'b0;
    end else begin
      if (start && !active) begin
        active      <= 1'b1;
        beat_addr   <= start_addr;
        beat_index  <= 8'd0;
        base_addr   <= start_addr;
        unsupported <= (burst_type == 2'b11) || (burst_size > 3'd3);
      end else if (active && beat_accept) begin
        if (beat_last) begin
          active <= 1'b0;
        end else begin
          beat_addr  <= next_addr;
          beat_index <= beat_index + 1'b1;
        end
      end
    end
  end
endmodule
