// SPDX-License-Identifier: MIT
// M32: cache-side subsystem integrating a 32-entry write buffer and 16-line victim cache.
`timescale 1ns/1ps
module ddr4_m32_cache_subsystem #(
  parameter integer ADDR_W=32,
  parameter integer DATA_W=32,
  parameter integer WRITE_BUFFER_DEPTH=32,
  parameter integer VICTIM_CACHE_LINES=16
)(
  input wire clk,input wire rst_n,
  input wire wr_valid,output wire wr_ready,input wire [ADDR_W-1:0] wr_addr,
  input wire [DATA_W-1:0] wr_data,input wire [DATA_W/8-1:0] wr_strb,
  output wire mem_wr_valid,input wire mem_wr_ready,output wire [ADDR_W-1:0] mem_wr_addr,
  output wire [DATA_W-1:0] mem_wr_data,output wire [DATA_W/8-1:0] mem_wr_strb,
  input wire victim_lookup_valid,input wire [ADDR_W-1:0] victim_lookup_addr,
  output wire victim_lookup_hit,output wire [DATA_W-1:0] victim_lookup_data,
  input wire victim_insert_valid,input wire [ADDR_W-1:0] victim_insert_addr,
  input wire [DATA_W-1:0] victim_insert_data,input wire victim_insert_dirty,
  output wire victim_evict_valid,input wire victim_evict_ready,
  output wire [ADDR_W-1:0] victim_evict_addr,output wire [DATA_W-1:0] victim_evict_data,
  output wire [$clog2(WRITE_BUFFER_DEPTH):0] write_buffer_count,
  input wire invalidate
);
  wire victim_lookup_dirty;
  wire victim_evict_dirty;
  ddr4_m30_write_buffer #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.DEPTH(WRITE_BUFFER_DEPTH)) u_wb(
    .clk(clk),.rst_n(rst_n),.in_valid(wr_valid),.in_ready(wr_ready),.in_addr(wr_addr),.in_data(wr_data),.in_strb(wr_strb),
    .out_valid(mem_wr_valid),.out_ready(mem_wr_ready),.out_addr(mem_wr_addr),.out_data(mem_wr_data),.out_strb(mem_wr_strb),.count(write_buffer_count));
  ddr4_m31_victim_cache #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.LINES(VICTIM_CACHE_LINES)) u_victim(
    .clk(clk),.rst_n(rst_n),.lookup_valid(victim_lookup_valid),.lookup_addr(victim_lookup_addr),.lookup_hit(victim_lookup_hit),
    .lookup_data(victim_lookup_data),.lookup_dirty(victim_lookup_dirty),.insert_valid(victim_insert_valid),.insert_addr(victim_insert_addr),
    .insert_data(victim_insert_data),.insert_dirty(victim_insert_dirty),.evict_valid(victim_evict_valid),.evict_ready(victim_evict_ready),
    .evict_addr(victim_evict_addr),.evict_data(victim_evict_data),.evict_dirty(victim_evict_dirty),.invalidate(invalidate));
endmodule
