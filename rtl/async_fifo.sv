`timescale 1ns/1ps
module async_fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 8,
  parameter int AW    = $clog2(DEPTH)
)(
  input  logic             wr_clk,
  input  logic             wr_rst_n,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             wr_full,
  output logic             wr_almost_full,

  input  logic             rd_clk,
  input  logic             rd_rst_n,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             rd_empty
);
  if ((DEPTH < 4) || ((DEPTH & (DEPTH-1)) != 0)) begin : g_invalid_depth
    invalid_async_fifo_depth_must_be_power_of_two_and_at_least_4 u_invalid_depth();
  end

  localparam logic [AW:0] ALMOST_FULL_LEVEL = DEPTH - 2;

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [AW:0] wbin, wgray, rbin, rgray;
  logic [AW:0] wgray_r1, wgray_r2, rgray_w1, rgray_w2;
  logic [AW:0] wbin_next, wgray_next, rbin_next, rgray_next;

  function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
    return (b >> 1) ^ b;
  endfunction

  function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
    logic [AW:0] b;
    b[AW] = g[AW];
    for(int i=AW-1;i>=0;i--) b[i] = b[i+1] ^ g[i];
    return b;
  endfunction

  assign wbin_next  = wbin + ((wr_en && !wr_full) ? 1'b1 : 1'b0);
  assign wgray_next = bin2gray(wbin_next);
  assign rbin_next  = rbin + ((rd_en && !rd_empty) ? 1'b1 : 1'b0);
  assign rgray_next = bin2gray(rbin_next);

  assign wr_full = (wgray_next == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});
  assign rd_empty = (rgray == wgray_r2);

  logic [AW:0] used_w;
  assign used_w = wbin - gray2bin(rgray_w2);
  assign wr_almost_full = (used_w >= ALMOST_FULL_LEVEL);

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if(!wr_rst_n) begin
      wbin <= '0; wgray <= '0; rgray_w1 <= '0; rgray_w2 <= '0;
    end else begin
      rgray_w1 <= rgray; rgray_w2 <= rgray_w1;
      if(wr_en && !wr_full) begin
        mem[wbin[AW-1:0]] <= wr_data;
        wbin <= wbin_next; wgray <= wgray_next;
      end
    end
  end

  assign rd_data = mem[rbin[AW-1:0]];

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if(!rd_rst_n) begin
      rbin <= '0; rgray <= '0; wgray_r1 <= '0; wgray_r2 <= '0;
    end else begin
      wgray_r1 <= wgray; wgray_r2 <= wgray_r1;
      if(rd_en && !rd_empty) begin
        rbin <= rbin_next; rgray <= rgray_next;
      end
    end
  end
endmodule
