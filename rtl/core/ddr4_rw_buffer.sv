// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_rw_buffer #(
  parameter int WIDTH = 64,
  parameter int DEPTH = 8
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             push,
  input  logic [WIDTH-1:0] push_data,
  input  logic             pop,
  output logic [WIDTH-1:0] pop_data,
  output logic             empty,
  output logic             full,
  output logic [$clog2(DEPTH+1)-1:0] level,
  output logic             overflow,
  output logic             underflow
);
  localparam int PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr, rd_ptr;

  assign empty = (level == 0);
  assign full  = (level == DEPTH);
  assign pop_data = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      level <= '0;
      overflow <= 1'b0;
      underflow <= 1'b0;
    end else begin
      overflow <= push && full && !pop;
      underflow <= pop && empty && !push;
      unique case ({push && !full, pop && !empty})
        2'b10: begin
          mem[wr_ptr] <= push_data;
          wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
          level <= level + 1'b1;
        end
        2'b01: begin
          rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
          level <= level - 1'b1;
        end
        2'b11: begin
          mem[wr_ptr] <= push_data;
          wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
          rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
        end
        default: ;
      endcase
    end
  end
endmodule
