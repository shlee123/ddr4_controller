// SPDX-License-Identifier: MIT
// M30: parameterized write-combining buffer. Default depth is 32 entries.
`timescale 1ns/1ps
module ddr4_m30_write_buffer #(
  parameter integer ADDR_W=32,
  parameter integer DATA_W=32,
  parameter integer DEPTH=32,
  parameter integer PTR_W=$clog2(DEPTH)
)(
  input wire clk,input wire rst_n,
  input wire in_valid,output wire in_ready,
  input wire [ADDR_W-1:0] in_addr,input wire [DATA_W-1:0] in_data,
  input wire [DATA_W/8-1:0] in_strb,
  output wire out_valid,input wire out_ready,
  output wire [ADDR_W-1:0] out_addr,output wire [DATA_W-1:0] out_data,
  output wire [DATA_W/8-1:0] out_strb,
  output wire [PTR_W:0] count
);
  localparam integer STRB_W=DATA_W/8;
  reg [ADDR_W-1:0] addr_m[0:DEPTH-1];
  reg [DATA_W-1:0] data_m[0:DEPTH-1];
  reg [STRB_W-1:0] strb_m[0:DEPTH-1];
  reg [PTR_W-1:0] wp,rp;
  reg [PTR_W:0] used;
  integer i,b;
  reg merge_found;
  reg [PTR_W-1:0] merge_idx;
  always @* begin
    merge_found=1'b0; merge_idx={PTR_W{1'b0}};
    for(i=0;i<DEPTH;i=i+1)
      if((i<used)&&!merge_found&&(addr_m[(rp+i)%DEPTH][ADDR_W-1:2]==in_addr[ADDR_W-1:2])) begin
        merge_found=1'b1; merge_idx=(rp+i)%DEPTH;
      end
  end
  assign in_ready=merge_found||(used<DEPTH);
  assign out_valid=(used!=0);
  assign out_addr=addr_m[rp]; assign out_data=data_m[rp]; assign out_strb=strb_m[rp];
  assign count=used;
  wire push=in_valid&&in_ready;
  wire pop=out_valid&&out_ready;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      wp<=0;rp<=0;used<=0;
      for(i=0;i<DEPTH;i=i+1) begin addr_m[i]<=0;data_m[i]<=0;strb_m[i]<=0; end
    end else begin
      if(push) begin
        if(merge_found) begin
          for(b=0;b<STRB_W;b=b+1) if(in_strb[b]) data_m[merge_idx][8*b +: 8]<=in_data[8*b +: 8];
          strb_m[merge_idx]<=strb_m[merge_idx]|in_strb;
        end else begin
          addr_m[wp]<=in_addr; data_m[wp]<=in_data; strb_m[wp]<=in_strb; wp<=wp+1'b1;
        end
      end
      if(pop) rp<=rp+1'b1;
      case({push&&!merge_found,pop})
        2'b10:used<=used+1'b1;
        2'b01:used<=used-1'b1;
        default:used<=used;
      endcase
    end
  end
endmodule
