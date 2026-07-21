// SPDX-License-Identifier: MIT
// M29 bridge: M22 native request FIFOs -> M23-M28 engine -> serial DDR beat executor.
`timescale 1ns/1ps
import ddr4_ctrl_pkg::*;
module ddr4_m29_native_bridge #(
  parameter integer ADDR_W=32, DATA_W=32, ID_W=6,
  parameter integer TAG_W=4, PAYLOAD_DEPTH=16
)(
  input wire clk,input wire rst_n,
  input ddr_req_t wr_req,input wire wr_empty,output wire wr_pop,
  input ddr_req_t rd_req,input wire rd_empty,output wire rd_pop,
  output ddr_req_t sched_wr_req,output wire sched_wr_empty,input wire sched_wr_pop,
  output ddr_req_t sched_rd_req,output wire sched_rd_empty,input wire sched_rd_pop,
  input ddr_rsp_t sched_rsp,input wire sched_rsp_wr,output wire sched_rsp_full,
  output ddr_rsp_t bridge_rsp,output wire bridge_rsp_wr,input wire bridge_rsp_full,
  output wire refresh_req,output wire refresh_block,
  output wire protocol_error,output wire refresh_deadline_error
);
  wire req_sel_wr=!wr_empty;
  wire req_valid=!wr_empty||!rd_empty;
  wire req_ready;
  wire [ID_W-1:0]req_id=req_sel_wr?wr_req.id:rd_req.id;
  wire [ADDR_W-1:0]req_addr=req_sel_wr?wr_req.addr:rd_req.addr;
  wire [7:0]req_len=req_sel_wr?wr_req.len:rd_req.len;
  wire [2:0]req_size=req_sel_wr?wr_req.size:rd_req.size;
  wire [1:0]req_burst=req_sel_wr?wr_req.burst:rd_req.burst;
  assign wr_pop=req_valid&&req_ready&&req_sel_wr;
  assign rd_pop=req_valid&&req_ready&&!req_sel_wr;

  wire cmd_valid,cmd_ready,cmd_write,cmd_last;
  wire [TAG_W-1:0]cmd_tag;
  wire [ID_W-1:0]cmd_id;
  wire [ADDR_W-1:0]cmd_addr;
  wire [7:0]cmd_beat;
  wire b_valid,b_ready,r_valid,r_ready,r_last;
  wire [ID_W-1:0]b_id_unused,r_id;
  wire [1:0]b_resp,r_resp;
  wire [DATA_W-1:0]r_data;
  wire [7:0]outstanding_count,command_count;

  reg p_valid[0:PAYLOAD_DEPTH-1];
  reg [ID_W-1:0]p_id[0:PAYLOAD_DEPTH-1];
  reg [ADDR_W-1:0]p_addr[0:PAYLOAD_DEPTH-1];
  reg [DATA_W-1:0]p_data[0:PAYLOAD_DEPTH-1];
  reg [DATA_W/8-1:0]p_strb[0:PAYLOAD_DEPTH-1];
  integer i;
  reg p_free_found,p_match_found;
  reg [$clog2(PAYLOAD_DEPTH)-1:0]p_free_idx,p_match_idx;
  always @* begin
    p_free_found=0;p_free_idx=0;p_match_found=0;p_match_idx=0;
    for(i=0;i<PAYLOAD_DEPTH;i=i+1)begin
      if(!p_free_found&&!p_valid[i])begin p_free_found=1;p_free_idx=i;end
      if(!p_match_found&&p_valid[i]&&p_id[i]==cmd_id&&p_addr[i]==cmd_addr)begin p_match_found=1;p_match_idx=i;end
    end
  end

  wire [TAG_W+ID_W:0]meta_out;
  wire [TAG_W-1:0]cpl_tag=meta_out[TAG_W+ID_W:ID_W+1];
  wire cpl_write=meta_out[ID_W];
  wire [ID_W-1:0]cpl_id=meta_out[ID_W-1:0];
  wire meta_full,meta_empty;
  wire meta_push=cmd_valid&&cmd_ready;
  wire meta_pop=sched_rsp_wr&&!meta_empty;

  wire engine_req_valid=req_valid&&(!req_sel_wr||((wr_req.len==0)&&p_free_found));
  wire engine_protocol_error;
  ddr4_m23_m28_engine #(.ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W),.TAG_W(TAG_W))u_engine(
    .clk,.rst_n,.req_valid(engine_req_valid),.req_ready,.req_write(req_sel_wr),.req_id,.req_addr,.req_len,.req_size,.req_burst,
    .cmd_valid,.cmd_ready,.cmd_tag,.cmd_write,.cmd_id,.cmd_addr,.cmd_beat,.cmd_last,
    .cpl_valid(sched_rsp_wr&&!meta_empty),.cpl_tag,.cpl_rdata(sched_rsp.rdata),.cpl_resp(sched_rsp.resp),
    .b_valid,.b_ready,.b_id(b_id_unused),.b_resp,.r_valid,.r_ready,.r_id,.r_data,.r_resp,.r_last,
    .refresh_req,.refresh_ack(refresh_req),.refresh_block,.outstanding_count,.command_count,
    .protocol_error(engine_protocol_error),.refresh_deadline_error
  );
  assign protocol_error=engine_protocol_error||(req_valid&&req_sel_wr&&(wr_req.len!=0));

  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)for(i=0;i<PAYLOAD_DEPTH;i=i+1)begin p_valid[i]<=0;p_id[i]<=0;p_addr[i]<=0;p_data[i]<=0;p_strb[i]<=0;end
    else begin
      if(wr_pop)begin p_valid[p_free_idx]<=1;p_id[p_free_idx]<=wr_req.id;p_addr[p_free_idx]<=wr_req.addr;p_data[p_free_idx]<=wr_req.wdata;p_strb[p_free_idx]<=wr_req.wstrb;end
      if(cmd_valid&&cmd_ready&&cmd_write&&p_match_found)p_valid[p_match_idx]<=0;
    end
  end

  assign sched_wr_req={cmd_id,1'b1,cmd_addr,p_data[p_match_idx],p_strb[p_match_idx],8'd0,3'd2,2'b01};
  assign sched_rd_req={cmd_id,1'b0,cmd_addr,{DATA_W{1'b0}},{DATA_W/8{1'b0}},8'd0,3'd2,2'b01};
  assign sched_wr_empty=!(cmd_valid&&cmd_write&&p_match_found&&!meta_full);
  assign sched_rd_empty=!(cmd_valid&&!cmd_write&&!meta_full);
  assign cmd_ready=cmd_valid&&!meta_full?(cmd_write?(p_match_found&&sched_wr_pop):sched_rd_pop):1'b0;

  sync_fifo #(.WIDTH(TAG_W+ID_W+1),.DEPTH(16))u_meta_fifo(
    .clk,.rst_n,.wr_en(meta_push),.wr_data({cmd_tag,cmd_write,cmd_id}),.full(meta_full),
    .rd_en(meta_pop),.rd_data(meta_out),.empty(meta_empty));

  wire wb_full,wb_empty;wire [ID_W-1:0]wb_id;
  wire wb_push=sched_rsp_wr&&!meta_empty&&cpl_write;
  wire wb_pop=b_ready&&!wb_empty;
  sync_fifo #(.WIDTH(ID_W),.DEPTH(16))u_write_id_fifo(
    .clk,.rst_n,.wr_en(wb_push),.wr_data(cpl_id),.full(wb_full),
    .rd_en(wb_pop),.rd_data(wb_id),.empty(wb_empty));
  assign sched_rsp_full=meta_empty||bridge_rsp_full||(cpl_write&&wb_full);

  wire select_b=b_valid&&!wb_empty;
  assign bridge_rsp={select_b?wb_id:r_id,select_b,cmd_addr,select_b?{DATA_W{1'b0}}:r_data,select_b?b_resp:r_resp,select_b?1'b1:r_last};
  assign bridge_rsp_wr=(select_b||r_valid)&&!bridge_rsp_full;
  assign b_ready=bridge_rsp_wr&&select_b;
  assign r_ready=bridge_rsp_wr&&!select_b;
endmodule
