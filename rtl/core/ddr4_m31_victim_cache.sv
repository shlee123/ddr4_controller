// SPDX-License-Identifier: MIT
// M31: fully-associative victim cache. Default capacity is 16 cache lines.
`timescale 1ns/1ps
module ddr4_m31_victim_cache #(
  parameter integer ADDR_W=32,
  parameter integer DATA_W=32,
  parameter integer LINES=16,
  parameter integer IDX_W=$clog2(LINES)
)(
  input wire clk,input wire rst_n,
  input wire lookup_valid,input wire [ADDR_W-1:0] lookup_addr,
  output reg lookup_hit,output reg [DATA_W-1:0] lookup_data,output reg lookup_dirty,
  input wire insert_valid,input wire [ADDR_W-1:0] insert_addr,
  input wire [DATA_W-1:0] insert_data,input wire insert_dirty,
  output wire evict_valid,input wire evict_ready,
  output wire [ADDR_W-1:0] evict_addr,output wire [DATA_W-1:0] evict_data,
  output wire evict_dirty,
  input wire invalidate
);
  reg valid_m[0:LINES-1]; reg dirty_m[0:LINES-1];
  reg [ADDR_W-1:0] addr_m[0:LINES-1]; reg [DATA_W-1:0] data_m[0:LINES-1];
  reg [IDX_W-1:0] repl;
  reg hit_found; reg [IDX_W-1:0] hit_idx;
  integer i;
  always @* begin
    hit_found=0;hit_idx=0;lookup_hit=0;lookup_data=0;lookup_dirty=0;
    for(i=0;i<LINES;i=i+1) if(!hit_found&&valid_m[i]&&(addr_m[i][ADDR_W-1:2]==lookup_addr[ADDR_W-1:2])) begin
      hit_found=1;hit_idx=i;lookup_hit=lookup_valid;lookup_data=data_m[i];lookup_dirty=dirty_m[i];
    end
  end
  assign evict_valid=insert_valid&&valid_m[repl]&&dirty_m[repl];
  assign evict_addr=addr_m[repl];assign evict_data=data_m[repl];assign evict_dirty=dirty_m[repl];
  wire insert_take=insert_valid&&(!evict_valid||evict_ready);
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      repl<=0;
      for(i=0;i<LINES;i=i+1) begin valid_m[i]<=0;dirty_m[i]<=0;addr_m[i]<=0;data_m[i]<=0;end
    end else begin
      if(invalidate) begin
        for(i=0;i<LINES;i=i+1) begin valid_m[i]<=0;dirty_m[i]<=0;end
      end else begin
        if(lookup_valid&&hit_found) begin
          valid_m[hit_idx]<=0; dirty_m[hit_idx]<=0;
        end
        if(insert_take) begin
          valid_m[repl]<=1;dirty_m[repl]<=insert_dirty;addr_m[repl]<=insert_addr;data_m[repl]<=insert_data;
          repl<=repl+1'b1;
        end
      end
    end
  end
endmodule
