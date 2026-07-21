// SPDX-License-Identifier: MIT
// M23-M28 portable transaction, reorder, burst, bank scheduler and refresh engine.
`timescale 1ns/1ps
module ddr4_m23_m28_engine #(
  parameter integer ADDR_W=32,DATA_W=32,ID_W=6,TAG_W=4,
  parameter integer OUTSTANDING=16,REQ_DEPTH=8,CMD_DEPTH=16,RSP_DEPTH=16,
  parameter integer BANK_W=4,ROW_W=15,T_REFI=64,T_RFC=12
)(
  input wire clk,input wire rst_n,
  input wire req_valid,output reg req_ready,input wire req_write,input wire[ID_W-1:0]req_id,
  input wire[ADDR_W-1:0]req_addr,input wire[7:0]req_len,input wire[2:0]req_size,input wire[1:0]req_burst,
  output reg cmd_valid,input wire cmd_ready,output reg[TAG_W-1:0]cmd_tag,output reg cmd_write,
  output reg[ID_W-1:0]cmd_id,output reg[ADDR_W-1:0]cmd_addr,output reg[7:0]cmd_beat,output reg cmd_last,
  input wire cpl_valid,input wire[TAG_W-1:0]cpl_tag,input wire[DATA_W-1:0]cpl_rdata,input wire[1:0]cpl_resp,
  output reg b_valid,input wire b_ready,output reg[ID_W-1:0]b_id,output reg[1:0]b_resp,
  output reg r_valid,input wire r_ready,output reg[ID_W-1:0]r_id,output reg[DATA_W-1:0]r_data,output reg[1:0]r_resp,output reg r_last,
  output wire refresh_req,input wire refresh_ack,output wire refresh_block,
  output reg[7:0]outstanding_count,output reg[7:0]command_count,
  output reg protocol_error,output reg refresh_deadline_error
);
  localparam integer ID_COUNT=(1<<ID_W),REQ_AW=$clog2(REQ_DEPTH),CMD_AW=$clog2(CMD_DEPTH),RSP_AW=$clog2(RSP_DEPTH),OUT_AW=$clog2(OUTSTANDING);
  integer i,j;
  reg req_write_m[0:REQ_DEPTH-1];reg[ID_W-1:0]req_id_m[0:REQ_DEPTH-1];reg[ADDR_W-1:0]req_addr_m[0:REQ_DEPTH-1];
  reg[7:0]req_len_m[0:REQ_DEPTH-1];reg[2:0]req_size_m[0:REQ_DEPTH-1];reg[1:0]req_burst_m[0:REQ_DEPTH-1];reg[TAG_W-1:0]req_tag_m[0:REQ_DEPTH-1];reg[7:0]req_seq_m[0:REQ_DEPTH-1];
  reg[REQ_AW-1:0]req_wp,req_rp;reg[REQ_AW:0]req_count;
  reg out_v[0:OUTSTANDING-1],out_wr[0:OUTSTANDING-1];reg[ID_W-1:0]out_id[0:OUTSTANDING-1];reg[7:0]out_seq[0:OUTSTANDING-1],out_left[0:OUTSTANDING-1];
  reg[7:0]alloc_r_seq[0:ID_COUNT-1],alloc_b_seq[0:ID_COUNT-1],retire_r_seq[0:ID_COUNT-1],retire_b_seq[0:ID_COUNT-1];reg[OUT_AW-1:0]free_idx;reg free_found;
  reg exp_v,exp_wr;reg[ID_W-1:0]exp_id;reg[ADDR_W-1:0]exp_addr;reg[7:0]exp_len,exp_seq,exp_beat;reg[2:0]exp_size;reg[1:0]exp_burst;reg[TAG_W-1:0]exp_tag;
  reg cmd_v[0:CMD_DEPTH-1],cmd_wr_m[0:CMD_DEPTH-1],cmd_last_m[0:CMD_DEPTH-1];reg[TAG_W-1:0]cmd_tag_m[0:CMD_DEPTH-1];reg[ID_W-1:0]cmd_id_m[0:CMD_DEPTH-1];
  reg[ADDR_W-1:0]cmd_addr_m[0:CMD_DEPTH-1];reg[7:0]cmd_seq_m[0:CMD_DEPTH-1],cmd_beat_m[0:CMD_DEPTH-1],cmd_age_m[0:CMD_DEPTH-1];reg[BANK_W-1:0]cmd_bank_m[0:CMD_DEPTH-1];reg[ROW_W-1:0]cmd_row_m[0:CMD_DEPTH-1];
  reg[$clog2(CMD_DEPTH+1)-1:0]cmd_used;reg[CMD_AW-1:0]sel_idx;reg sel_found,sel_hit;reg[(1<<BANK_W)-1:0]open_valid;reg[ROW_W-1:0]open_row[0:(1<<BANK_W)-1];
  reg rr_v[0:RSP_DEPTH-1],rr_last_m[0:RSP_DEPTH-1];reg[ID_W-1:0]rr_id_m[0:RSP_DEPTH-1];reg[7:0]rr_seq_m[0:RSP_DEPTH-1];reg[DATA_W-1:0]rr_data_m[0:RSP_DEPTH-1];reg[1:0]rr_resp_m[0:RSP_DEPTH-1];reg[RSP_AW-1:0]r_sel;reg r_found;
  reg[ID_W-1:0]b_id_m[0:RSP_DEPTH-1];reg[1:0]b_resp_m[0:RSP_DEPTH-1];reg[RSP_AW-1:0]b_wp,b_rp;reg[RSP_AW:0]b_count;reg[15:0]refi_cnt,rfc_cnt;reg refresh_pending;
  function [ADDR_W-1:0] calc_addr;
    input[ADDR_W-1:0]base_addr;input[7:0]len;input[2:0]size;input[1:0]burst;input[7:0]beat;reg[ADDR_W-1:0]bytes,incr,wrap_bytes,wrap_base;
    begin bytes={{(ADDR_W-1){1'b0}},1'b1}<<size;incr=bytes*beat;wrap_bytes=bytes*(len+1'b1);wrap_base=base_addr&~(wrap_bytes-1'b1);if(burst==2'b00)calc_addr=base_addr;else if(burst==2'b10)calc_addr=wrap_base|((base_addr+incr)&(wrap_bytes-1'b1));else calc_addr=base_addr+incr;end
  endfunction
  wire[ADDR_W-1:0]exp_addr_now=calc_addr(exp_addr,exp_len,exp_size,exp_burst,exp_beat);
  wire req_push=req_valid&&req_ready;wire req_pop=!exp_v&&(req_count!=0);
  wire cmd_push=exp_v&&(cmd_used<CMD_DEPTH);wire cmd_pop=cmd_valid&&cmd_ready;
  wire[7:0]req_alloc_seq=req_write?alloc_b_seq[req_id]:alloc_r_seq[req_id];
  always @* begin free_found=0;free_idx=0;for(i=0;i<OUTSTANDING;i=i+1)if(!free_found&&!out_v[i])begin free_found=1;free_idx=i;end req_ready=(req_count<REQ_DEPTH)&&free_found;outstanding_count=0;for(i=0;i<OUTSTANDING;i=i+1)if(out_v[i])outstanding_count=outstanding_count+1'b1;command_count=cmd_used;end
  always @* begin sel_found=0;sel_idx=0;sel_hit=0;for(i=0;i<CMD_DEPTH;i=i+1)if(cmd_v[i])begin if(!sel_found)begin sel_found=1;sel_idx=i;sel_hit=open_valid[cmd_bank_m[i]]&&(open_row[cmd_bank_m[i]]==cmd_row_m[i]);end else if((open_valid[cmd_bank_m[i]]&&(open_row[cmd_bank_m[i]]==cmd_row_m[i]))&&!sel_hit)begin sel_idx=i;sel_hit=1;end else if(((open_valid[cmd_bank_m[i]]&&(open_row[cmd_bank_m[i]]==cmd_row_m[i]))==sel_hit)&&(cmd_age_m[i]>cmd_age_m[sel_idx]))sel_idx=i;end cmd_valid=sel_found&&!refresh_block;cmd_tag=cmd_tag_m[sel_idx];cmd_write=cmd_wr_m[sel_idx];cmd_id=cmd_id_m[sel_idx];cmd_addr=cmd_addr_m[sel_idx];cmd_beat=cmd_beat_m[sel_idx];cmd_last=cmd_last_m[sel_idx];end
  always @* begin r_found=0;r_sel=0;for(i=0;i<RSP_DEPTH;i=i+1)if(!r_found&&rr_v[i]&&(rr_seq_m[i]==retire_r_seq[rr_id_m[i]]))begin r_found=1;r_sel=i;end r_valid=r_found;r_id=rr_id_m[r_sel];r_data=rr_data_m[r_sel];r_resp=rr_resp_m[r_sel];r_last=rr_last_m[r_sel];b_valid=(b_count!=0);b_id=b_id_m[b_rp];b_resp=b_resp_m[b_rp];end
  assign refresh_req=refresh_pending;assign refresh_block=refresh_pending||(rfc_cnt!=0);
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
      req_wp<=0;req_rp<=0;req_count<=0;exp_v<=0;exp_wr<=0;exp_id<=0;exp_addr<=0;exp_len<=0;exp_size<=0;exp_burst<=0;exp_tag<=0;exp_seq<=0;exp_beat<=0;cmd_used<=0;b_wp<=0;b_rp<=0;b_count<=0;protocol_error<=0;refi_cnt<=T_REFI-1;rfc_cnt<=0;refresh_pending<=0;refresh_deadline_error<=0;open_valid<=0;
      for(i=0;i<REQ_DEPTH;i=i+1)begin req_write_m[i]<=0;req_id_m[i]<=0;req_addr_m[i]<=0;req_len_m[i]<=0;req_size_m[i]<=0;req_burst_m[i]<=0;req_tag_m[i]<=0;req_seq_m[i]<=0;end
      for(i=0;i<OUTSTANDING;i=i+1)begin out_v[i]<=0;out_wr[i]<=0;out_id[i]<=0;out_seq[i]<=0;out_left[i]<=0;end
      for(i=0;i<CMD_DEPTH;i=i+1)begin cmd_v[i]<=0;cmd_wr_m[i]<=0;cmd_last_m[i]<=0;cmd_tag_m[i]<=0;cmd_id_m[i]<=0;cmd_addr_m[i]<=0;cmd_seq_m[i]<=0;cmd_beat_m[i]<=0;cmd_age_m[i]<=0;cmd_bank_m[i]<=0;cmd_row_m[i]<=0;end
      for(i=0;i<RSP_DEPTH;i=i+1)begin rr_v[i]<=0;rr_last_m[i]<=0;rr_id_m[i]<=0;rr_seq_m[i]<=0;rr_data_m[i]<=0;rr_resp_m[i]<=0;b_id_m[i]<=0;b_resp_m[i]<=0;end
      for(i=0;i<ID_COUNT;i=i+1)begin alloc_r_seq[i]<=0;alloc_b_seq[i]<=0;retire_r_seq[i]<=0;retire_b_seq[i]<=0;end for(i=0;i<(1<<BANK_W);i=i+1)open_row[i]<=0;
    end else begin
      if(refi_cnt!=0)refi_cnt<=refi_cnt-1'b1;else begin if(refresh_pending)refresh_deadline_error<=1;refresh_pending<=1;refi_cnt<=T_REFI-1;end
      if(refresh_pending&&refresh_ack)begin refresh_pending<=0;rfc_cnt<=T_RFC;open_valid<=0;end else if(rfc_cnt!=0)rfc_cnt<=rfc_cnt-1'b1;
      if(req_push)begin req_write_m[req_wp]<=req_write;req_id_m[req_wp]<=req_id;req_addr_m[req_wp]<=req_addr;req_len_m[req_wp]<=req_len;req_size_m[req_wp]<=req_size;req_burst_m[req_wp]<=req_burst;req_tag_m[req_wp]<=free_idx;req_seq_m[req_wp]<=req_alloc_seq;req_wp<=req_wp+1'b1;if(req_write)alloc_b_seq[req_id]<=alloc_b_seq[req_id]+1'b1;else alloc_r_seq[req_id]<=alloc_r_seq[req_id]+1'b1;out_v[free_idx]<=1;out_wr[free_idx]<=req_write;out_id[free_idx]<=req_id;out_seq[free_idx]<=req_alloc_seq;out_left[free_idx]<=req_len+1'b1;if(req_size>3'd6||req_burst==2'b11)protocol_error<=1;end
      if(req_pop)begin exp_wr<=req_write_m[req_rp];exp_id<=req_id_m[req_rp];exp_addr<=req_addr_m[req_rp];exp_len<=req_len_m[req_rp];exp_size<=req_size_m[req_rp];exp_burst<=req_burst_m[req_rp];exp_tag<=req_tag_m[req_rp];exp_seq<=req_seq_m[req_rp];exp_beat<=0;exp_v<=1;req_rp<=req_rp+1'b1;end
      case({req_push,req_pop})2'b10:req_count<=req_count+1'b1;2'b01:req_count<=req_count-1'b1;default:req_count<=req_count;endcase
      if(cmd_push)begin for(j=0;j<CMD_DEPTH;j=j+1)if(!cmd_v[j])begin cmd_v[j]<=1;cmd_wr_m[j]<=exp_wr;cmd_id_m[j]<=exp_id;cmd_tag_m[j]<=exp_tag;cmd_seq_m[j]<=exp_seq;cmd_addr_m[j]<=exp_addr_now;cmd_beat_m[j]<=exp_beat;cmd_last_m[j]<=(exp_beat==exp_len);cmd_bank_m[j]<=exp_addr_now[6 +: BANK_W];cmd_row_m[j]<=exp_addr_now[10 +: ROW_W];cmd_age_m[j]<=0;if(exp_beat==exp_len)exp_v<=0;else exp_beat<=exp_beat+1'b1;j=CMD_DEPTH;end end
      for(i=0;i<CMD_DEPTH;i=i+1)if(cmd_v[i]&&cmd_age_m[i]!=8'hff)cmd_age_m[i]<=cmd_age_m[i]+1'b1;
      if(cmd_pop)begin open_valid[cmd_bank_m[sel_idx]]<=1;open_row[cmd_bank_m[sel_idx]]<=cmd_row_m[sel_idx];cmd_v[sel_idx]<=0;end
      case({cmd_push,cmd_pop})2'b10:cmd_used<=cmd_used+1'b1;2'b01:cmd_used<=cmd_used-1'b1;default:cmd_used<=cmd_used;endcase
      if(cpl_valid)begin if(!out_v[cpl_tag])protocol_error<=1;else begin if(out_left[cpl_tag]!=0)out_left[cpl_tag]<=out_left[cpl_tag]-1'b1;if(out_wr[cpl_tag])begin if(out_left[cpl_tag]==1)begin if(b_count<RSP_DEPTH)begin b_id_m[b_wp]<=out_id[cpl_tag];b_resp_m[b_wp]<=cpl_resp;b_wp<=b_wp+1'b1;b_count<=b_count+1'b1;out_v[cpl_tag]<=0;end else protocol_error<=1;end end else begin for(j=0;j<RSP_DEPTH;j=j+1)if(!rr_v[j])begin rr_v[j]<=1;rr_id_m[j]<=out_id[cpl_tag];rr_seq_m[j]<=out_seq[cpl_tag];rr_data_m[j]<=cpl_rdata;rr_resp_m[j]<=cpl_resp;rr_last_m[j]<=(out_left[cpl_tag]==1);if(out_left[cpl_tag]==1)out_v[cpl_tag]<=0;j=RSP_DEPTH;end end end end
      if(b_valid&&b_ready)begin retire_b_seq[b_id]<=retire_b_seq[b_id]+1'b1;b_rp<=b_rp+1'b1;b_count<=b_count-1'b1;end
      if(r_valid&&r_ready)begin rr_v[r_sel]<=0;if(r_last)retire_r_seq[r_id]<=retire_r_seq[r_id]+1'b1;end
    end
  end
endmodule
