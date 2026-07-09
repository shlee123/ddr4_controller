`timescale 1ns/1ps
module sync_fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 8,
  parameter int AW    = $clog2(DEPTH)
)(
  input  logic clk,
  input  logic rst_n,
  input  logic wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic full,
  input  logic rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic empty
);
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [AW:0] wptr,rptr,count;
  assign full = (count == DEPTH);
  assign empty = (count == 0);
  assign rd_data = mem[rptr[AW-1:0]];
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin wptr<='0; rptr<='0; count<='0; end
    else begin
      if(wr_en && !full) begin mem[wptr[AW-1:0]] <= wr_data; wptr <= wptr + 1'b1; end
      if(rd_en && !empty) rptr <= rptr + 1'b1;
      unique case({wr_en && !full, rd_en && !empty})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end
endmodule
