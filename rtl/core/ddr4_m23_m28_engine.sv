// SPDX-License-Identifier: MIT
// M23-M28 transaction, reorder, burst, bank scheduling and refresh engine.
`timescale 1ns/1ps

module ddr4_m23_m28_engine #(
  parameter int ADDR_W=32,
  parameter int DATA_W=32,
  parameter int ID_W=6,
  parameter int TAG_W=4,
  parameter int OUTSTANDING=16,
  parameter int REQ_DEPTH=8,
  parameter int CMD_DEPTH=16,
  parameter int RSP_DEPTH=16,
  parameter int BANK_W=4,
  parameter int ROW_W=15,
  parameter int T_REFI=64,
  parameter int T_RFC=12
)(
  input  logic clk,input logic rst_n,
  input  logic req_valid,output logic req_ready,
  input  logic req_write,input logic [ID_W-1:0] req_id,
  input  logic [ADDR_W-1:0] req_addr,input logic [7:0] req_len,
  input  logic [2:0] req_size,input logic [1:0] req_burst,
  output logic cmd_valid,input logic cmd_ready,
  output logic [TAG_W-1:0] cmd_tag,output logic cmd_write,
  output logic [ID_W-1:0] cmd_id,output logic [ADDR_W-1:0] cmd_addr,
  output logic [7:0] cmd_beat,output logic cmd_last,
  input  logic cpl_valid,input logic [TAG_W-1:0] cpl_tag,
  input  logic [DATA_W-1:0] cpl_rdata,input logic [1:0] cpl_resp,
  output logic b_valid,input logic b_ready,output logic [ID_W-1:0] b_id,output logic [1:0] b_resp,
  output logic r_valid,input logic r_ready,output logic [ID_W-1:0] r_id,
  output logic [DATA_W-1:0] r_data,output logic [1:0] r_resp,output logic r_last,
  output logic refresh_req,input logic refresh_ack,output logic refresh_block,
  output logic [7:0] outstanding_count,output logic [7:0] command_count,
  output logic protocol_error,output logic refresh_deadline_error
);
  localparam int ID_COUNT=(1<<ID_W);
  localparam int REQ_AW=$clog2(REQ_DEPTH),CMD_AW=$clog2(CMD_DEPTH),RSP_AW=$clog2(RSP_DEPTH);
  localparam int OUT_AW=$clog2(OUTSTANDING);

  typedef struct packed {
    logic write; logic [ID_W-1:0] id; logic [ADDR_W-1:0] addr;
    logic [7:0] len; logic [2:0] size; logic [1:0] burst;
    logic [TAG_W-1:0] tag; logic [7:0] seq;
  } txn_t;
  typedef struct packed {
    logic valid; logic write; logic [ID_W-1:0] id; logic [7:0] seq;
    logic [7:0] beats_left;
  } out_t;
  typedef struct packed {
    logic valid; logic [TAG_W-1:0] tag; logic write; logic [ID_W-1:0] id;
    logic [7:0] seq; logic [ADDR_W-1:0] addr; logic [7:0] beat; logic last;
    logic [BANK_W-1:0] bank; logic [ROW_W-1:0] row; logic [7:0] age;
  } cmd_t;
  typedef struct packed {
    logic valid; logic [ID_W-1:0] id; logic [7:0] seq;
    logic [DATA_W-1:0] data; logic [1:0] resp; logic last;
  } rr_t;
  typedef struct packed {logic [ID_W-1:0] id;logic [1:0] resp;} b_t;

  txn_t req_mem[0:REQ_DEPTH-1];
  logic [REQ_AW-1:0] req_wp,req_rp; logic [REQ_AW:0] req_count;
  out_t out_tab[0:OUTSTANDING-1];
  logic [7:0] alloc_seq[0:ID_COUNT-1],retire_r_seq[0:ID_COUNT-1],retire_b_seq[0:ID_COUNT-1];
  logic [OUT_AW-1:0] free_idx; logic free_found;

  logic exp_valid; txn_t exp_txn; logic [7:0] exp_beat;
  cmd_t cmd_q[0:CMD_DEPTH-1];
  logic [$clog2(CMD_DEPTH+1)-1:0] cmd_used;
  logic [CMD_AW-1:0] sel_idx; logic sel_found; logic sel_hit;
  logic [(1<<BANK_W)-1:0] open_valid; logic [ROW_W-1:0] open_row[0:(1<<BANK_W)-1];

  rr_t rr[0:RSP_DEPTH-1];
  b_t bq[0:RSP_DEPTH-1]; logic [RSP_AW-1:0] b_wp,b_rp; logic [RSP_AW:0] b_count;
  logic [RSP_AW-1:0] r_sel; logic r_found;

  logic [15:0] refi_cnt,rfc_cnt; logic refresh_pending;
  integer i,j;

  always_comb begin
    free_found=1'b0;free_idx='0;
    for(i=0;i<OUTSTANDING;i=i+1) if(!free_found&&!out_tab[i].valid) begin free_found=1'b1;free_idx=i[OUT_AW-1:0];end
    req_ready=(req_count<REQ_DEPTH)&&free_found;
    outstanding_count='0;
    for(i=0;i<OUTSTANDING;i=i+1) if(out_tab[i].valid) outstanding_count=outstanding_count+1'b1;
    command_count=cmd_used;
  end

  function automatic [ADDR_W-1:0] beat_addr(input txn_t t,input logic [7:0] beat);
    logic [ADDR_W-1:0] incr,bytes,wrap_bytes,base;
    begin
      bytes={{(ADDR_W-1){1'b0}},1'b1}<<t.size;
      incr=bytes*beat;
      wrap_bytes=bytes*(t.len+1'b1);
      base=t.addr & ~(wrap_bytes-1'b1);
      case(t.burst)
        2'b00:beat_addr=t.addr;
        2'b10:beat_addr=base|((t.addr+incr)&(wrap_bytes-1'b1));
        default:beat_addr=t.addr+incr;
      endcase
    end
  endfunction

  always_comb begin
    sel_found=1'b0;sel_idx='0;sel_hit=1'b0;
    for(i=0;i<CMD_DEPTH;i=i+1) begin
      if(cmd_q[i].valid) begin
        if(!sel_found) begin sel_found=1'b1;sel_idx=i[CMD_AW-1:0];sel_hit=open_valid[cmd_q[i].bank]&&(open_row[cmd_q[i].bank]==cmd_q[i].row);end
        else if((open_valid[cmd_q[i].bank]&&(open_row[cmd_q[i].bank]==cmd_q[i].row))&&!sel_hit) begin sel_idx=i[CMD_AW-1:0];sel_hit=1'b1;end
        else if(((open_valid[cmd_q[i].bank]&&(open_row[cmd_q[i].bank]==cmd_q[i].row))==sel_hit)&&(cmd_q[i].age>cmd_q[sel_idx].age)) sel_idx=i[CMD_AW-1:0];
      end
    end
    cmd_valid=sel_found&&!refresh_block;
    cmd_tag=cmd_q[sel_idx].tag;cmd_write=cmd_q[sel_idx].write;cmd_id=cmd_q[sel_idx].id;
    cmd_addr=cmd_q[sel_idx].addr;cmd_beat=cmd_q[sel_idx].beat;cmd_last=cmd_q[sel_idx].last;
  end

  always_comb begin
    r_found=1'b0;r_sel='0;
    for(i=0;i<RSP_DEPTH;i=i+1) if(!r_found&&rr[i].valid&&(rr[i].seq==retire_r_seq[rr[i].id])) begin r_found=1'b1;r_sel=i[RSP_AW-1:0];end
    r_valid=r_found;r_id=rr[r_sel].id;r_data=rr[r_sel].data;r_resp=rr[r_sel].resp;r_last=rr[r_sel].last;
    b_valid=(b_count!=0);b_id=bq[b_rp].id;b_resp=bq[b_rp].resp;
  end

  assign refresh_req=refresh_pending;
  assign refresh_block=refresh_pending||(rfc_cnt!=0);

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      req_wp<='0;req_rp<='0;req_count<='0;exp_valid<=0;exp_txn<='0;exp_beat<=0;
      cmd_used<='0;b_wp<='0;b_rp<='0;b_count<='0;protocol_error<=0;
      refi_cnt<=T_REFI-1; rfc_cnt<=0;refresh_pending<=0;refresh_deadline_error<=0;
      open_valid<='0;
      for(i=0;i<REQ_DEPTH;i=i+1)req_mem[i]<='0;
      for(i=0;i<OUTSTANDING;i=i+1)out_tab[i]<='0;
      for(i=0;i<CMD_DEPTH;i=i+1)cmd_q[i]<='0;
      for(i=0;i<RSP_DEPTH;i=i+1)begin rr[i]<='0;bq[i]<='0;end
      for(i=0;i<ID_COUNT;i=i+1)begin alloc_seq[i]<=0;retire_r_seq[i]<=0;retire_b_seq[i]<=0;end
      for(i=0;i<(1<<BANK_W);i=i+1)open_row[i]<='0;
    end else begin
      if(refi_cnt!=0) refi_cnt<=refi_cnt-1'b1;
      else begin
        if(refresh_pending) refresh_deadline_error<=1'b1;
        refresh_pending<=1'b1;refi_cnt<=T_REFI-1;
      end
      if(refresh_pending&&refresh_ack) begin refresh_pending<=0;rfc_cnt<=T_RFC;open_valid<='0;end
      else if(rfc_cnt!=0) rfc_cnt<=rfc_cnt-1'b1;

      if(req_valid&&req_ready) begin
        req_mem[req_wp].write<=req_write;req_mem[req_wp].id<=req_id;req_mem[req_wp].addr<=req_addr;
        req_mem[req_wp].len<=req_len;req_mem[req_wp].size<=req_size;req_mem[req_wp].burst<=req_burst;
        req_mem[req_wp].tag<=free_idx;req_mem[req_wp].seq<=alloc_seq[req_id];
        req_wp<=req_wp+1'b1;req_count<=req_count+1'b1;alloc_seq[req_id]<=alloc_seq[req_id]+1'b1;
        out_tab[free_idx].valid<=1'b1;out_tab[free_idx].write<=req_write;out_tab[free_idx].id<=req_id;
        out_tab[free_idx].seq<=alloc_seq[req_id];out_tab[free_idx].beats_left<=req_len+1'b1;
        if(req_size>3'd6||req_burst==2'b11)protocol_error<=1'b1;
      end

      if(!exp_valid&&(req_count!=0)) begin exp_txn<=req_mem[req_rp];exp_beat<=0;exp_valid<=1;req_rp<=req_rp+1'b1;req_count<=req_count-1'b1;end
      if(exp_valid&&(cmd_used<CMD_DEPTH)) begin
        for(j=0;j<CMD_DEPTH;j=j+1) if(!cmd_q[j].valid) begin
          cmd_q[j].valid<=1;cmd_q[j].tag<=exp_txn.tag;cmd_q[j].write<=exp_txn.write;cmd_q[j].id<=exp_txn.id;cmd_q[j].seq<=exp_txn.seq;
          cmd_q[j].addr<=beat_addr(exp_txn,exp_beat);cmd_q[j].beat<=exp_beat;cmd_q[j].last<=(exp_beat==exp_txn.len);
          cmd_q[j].bank<=beat_addr(exp_txn,exp_beat)[6 +: BANK_W];cmd_q[j].row<=beat_addr(exp_txn,exp_beat)[10 +: ROW_W];cmd_q[j].age<=0;
          cmd_used<=cmd_used+1'b1;
          if(exp_beat==exp_txn.len)exp_valid<=0;else exp_beat<=exp_beat+1'b1;
          j=CMD_DEPTH;
        end
      end
      for(i=0;i<CMD_DEPTH;i=i+1)if(cmd_q[i].valid&&cmd_q[i].age!=8'hff)cmd_q[i].age<=cmd_q[i].age+1'b1;
      if(cmd_valid&&cmd_ready) begin
        open_valid[cmd_q[sel_idx].bank]<=1'b1;open_row[cmd_q[sel_idx].bank]<=cmd_q[sel_idx].row;
        cmd_q[sel_idx].valid<=0;cmd_used<=cmd_used-1'b1;
      end

      if(cpl_valid) begin
        if(!out_tab[cpl_tag].valid) protocol_error<=1'b1;
        else begin
          if(out_tab[cpl_tag].beats_left!=0)out_tab[cpl_tag].beats_left<=out_tab[cpl_tag].beats_left-1'b1;
          if(out_tab[cpl_tag].write) begin
            if(out_tab[cpl_tag].beats_left==1) begin
              if(b_count<RSP_DEPTH)begin bq[b_wp].id<=out_tab[cpl_tag].id;bq[b_wp].resp<=cpl_resp;b_wp<=b_wp+1'b1;b_count<=b_count+1'b1;out_tab[cpl_tag].valid<=0;end
              else protocol_error<=1'b1;
            end
          end else begin
            for(j=0;j<RSP_DEPTH;j=j+1)if(!rr[j].valid)begin
              rr[j].valid<=1;rr[j].id<=out_tab[cpl_tag].id;rr[j].seq<=out_tab[cpl_tag].seq;rr[j].data<=cpl_rdata;rr[j].resp<=cpl_resp;rr[j].last<=(out_tab[cpl_tag].beats_left==1);
              if(out_tab[cpl_tag].beats_left==1)out_tab[cpl_tag].valid<=0;
              j=RSP_DEPTH;
            end
          end
        end
      end
      if(b_valid&&b_ready)begin retire_b_seq[b_id]<=retire_b_seq[b_id]+1'b1;b_rp<=b_rp+1'b1;b_count<=b_count-1'b1;end
      if(r_valid&&r_ready)begin rr[r_sel].valid<=0;if(r_last)retire_r_seq[r_id]<=retire_r_seq[r_id]+1'b1;end
    end
  end
endmodule
