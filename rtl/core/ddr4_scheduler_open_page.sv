// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
import ddr4_ctrl_pkg::*;

module ddr4_scheduler_open_page #(
  parameter integer AXI_ADDR_W=32,AXI_DATA_W=32,DDR_ADDR_W=17,
  parameter integer DDR_BG_W=2,DDR_BA_W=2,DDR_DQ_W=16,DDR_DM_W=DDR_DQ_W/8
)(
  input wire clk,input wire rst_n,input wire init_start,output reg init_done,input wire[16:0]mr[0:6],
  input ddr_req_t wr_req_data,input wire wr_req_empty,output reg wr_req_rd,
  input ddr_req_t rd_req_data,input wire rd_req_empty,output reg rd_req_rd,
  output ddr_rsp_t rsp_data,output reg rsp_wr,input wire rsp_full,
  output wire[AXI_ADDR_W-1:0]cache_lookup_addr,input wire cache_hit,input wire[AXI_DATA_W-1:0]cache_lookup_data,
  output reg cache_write_valid,output reg[AXI_ADDR_W-1:0]cache_write_addr,output reg[AXI_DATA_W-1:0]cache_write_data,
  output reg ddr_reset_n,output reg ddr_cke,output reg ddr_cs_n,output reg ddr_act_n,output reg ddr_ras_n,output reg ddr_cas_n,output reg ddr_we_n,
  output reg[DDR_BG_W-1:0]ddr_bg,output reg[DDR_BA_W-1:0]ddr_ba,output reg[DDR_ADDR_W-1:0]ddr_a,output reg ddr_odt,output reg ddr_par,
  input wire[DDR_DQ_W-1:0]ddr_dq_in,output wire[DDR_DQ_W-1:0]ddr_dq_out,output wire ddr_dq_oe,
  output wire[DDR_DM_W-1:0]ddr_dqs_t_out,output wire[DDR_DM_W-1:0]ddr_dqs_c_out,output wire ddr_dqs_oe,
  output wire[DDR_DM_W-1:0]ddr_dm_n_out,output wire ddr_dm_oe
);
  localparam integer BANKS=(1<<(DDR_BG_W+DDR_BA_W));
  typedef enum reg[4:0]{S_RESET,S_INIT,S_IDLE,S_LOOKUP,S_PRE,S_TRP,S_ACT,S_TRCD,S_WR,S_WWAIT,S_RD,S_RLAT,S_RCAP,S_RESP}state_t;
  state_t state;
  reg[15:0]wait_cnt;
  ddr_req_t cur_req;
  reg rsp_valid;
  reg[AXI_DATA_W-1:0]rsp_rdata;
  reg[BANKS-1:0]open_valid;
  reg[DDR_ROW_W-1:0]open_row[0:BANKS-1];
  integer i;

  wire[DDR_COL_W-1:0]map_col;wire[DDR_BA_W-1:0]map_ba;wire[DDR_BG_W-1:0]map_bg;wire[DDR_ROW_W-1:0]map_row;
  wire[DDR_BG_W+DDR_BA_W-1:0]bank_index={map_bg,map_ba};
  wire row_hit=open_valid[bank_index]&&(open_row[bank_index]==map_row);
  ddr4_address_mapper #(.AXI_ADDR_W(AXI_ADDR_W),.COL_W(DDR_COL_W),.BA_W(DDR_BA_W),.BG_W(DDR_BG_W),.ROW_W(DDR_ROW_W))u_map(.axi_addr(cur_req.addr),.col(map_col),.bank(map_ba),.bank_group(map_bg),.row(map_row));

  reg phy_wr_enable,phy_rd_capture;
  wire[AXI_DATA_W-1:0]phy_rd_data;wire phy_rd_valid;
  ddr4_x16_data_path #(.AXI_DATA_W(AXI_DATA_W),.DQ_W(DDR_DQ_W),.DM_W(DDR_DM_W))u_dp(
    .clk,.rst_n,.wr_enable(phy_wr_enable),.wr_data(cur_req.wdata),.wr_strb(cur_req.wstrb),
    .dq_out(ddr_dq_out),.dm_n_out(ddr_dm_n_out),.dq_oe(ddr_dq_oe),.dqs_oe(ddr_dqs_oe),.dqs_t_out(ddr_dqs_t_out),.dqs_c_out(ddr_dqs_c_out),
    .rd_capture_enable(phy_rd_capture),.dq_in(ddr_dq_in),.rd_data(phy_rd_data),.rd_data_valid(phy_rd_valid));
  assign ddr_dm_oe=ddr_dq_oe;
  assign cache_lookup_addr=cur_req.addr;
  assign rsp_data={cur_req.id,cur_req.wr,cur_req.addr,rsp_rdata,2'b00,1'b1};

  always @* begin
    wr_req_rd=0;rd_req_rd=0;
    if(state==S_IDLE&&!rsp_valid)begin if(!rd_req_empty)rd_req_rd=1;else if(!wr_req_empty)wr_req_rd=1;end
  end

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
      state<=S_RESET;wait_cnt<=0;init_done<=0;ddr_reset_n<=0;ddr_cke<=0;ddr_cs_n<=1;ddr_act_n<=1;ddr_ras_n<=1;ddr_cas_n<=1;ddr_we_n<=1;ddr_bg<=0;ddr_ba<=0;ddr_a<=0;ddr_odt<=0;ddr_par<=0;
      cur_req<='0;rsp_valid<=0;rsp_wr<=0;rsp_rdata<=0;cache_write_valid<=0;cache_write_addr<=0;cache_write_data<=0;open_valid<=0;phy_wr_enable<=0;phy_rd_capture<=0;
      for(i=0;i<BANKS;i=i+1)open_row[i]<=0;
    end else begin
      ddr_cs_n<=1;ddr_act_n<=1;ddr_ras_n<=1;ddr_cas_n<=1;ddr_we_n<=1;ddr_reset_n<=1;ddr_cke<=1;ddr_odt<=1;ddr_par<=0;
      rsp_wr<=0;cache_write_valid<=0;phy_wr_enable<=0;
      if(wait_cnt!=0)wait_cnt<=wait_cnt-1'b1;
      case(state)
        S_RESET:begin if(init_start)begin wait_cnt<=16'd32;state<=S_INIT;end end
        S_INIT:begin if(wait_cnt==0)begin init_done<=1;state<=S_IDLE;end end
        S_IDLE:begin
          if(rd_req_rd)begin cur_req<=rd_req_data;state<=S_LOOKUP;end
          else if(wr_req_rd)begin cur_req<=wr_req_data;state<=S_LOOKUP;end
        end
        S_LOOKUP:begin
          if(!cur_req.wr&&cache_hit)begin rsp_rdata<=cache_lookup_data;state<=S_RESP;end
          else if(row_hit)begin if(cur_req.wr)state<=S_WR;else state<=S_RD;end
          else if(open_valid[bank_index])state<=S_PRE;
          else state<=S_ACT;
        end
        S_PRE:begin ddr_cs_n<=0;ddr_act_n<=1;ddr_ras_n<=0;ddr_cas_n<=1;ddr_we_n<=0;ddr_bg<=map_bg;ddr_ba<=map_ba;ddr_a<=0;ddr_a[10]<=0;open_valid[bank_index]<=0;wait_cnt<=T_RP_CK;state<=S_TRP;end
        S_TRP:if(wait_cnt==0)state<=S_ACT;
        S_ACT:begin ddr_cs_n<=0;ddr_act_n<=0;ddr_bg<=map_bg;ddr_ba<=map_ba;ddr_a<=DDR_ADDR_W'(map_row);open_valid[bank_index]<=1;open_row[bank_index]<=map_row;wait_cnt<=T_RCD_CK;state<=S_TRCD;end
        S_TRCD:if(wait_cnt==0)begin if(cur_req.wr)state<=S_WR;else state<=S_RD;end
        S_WR:begin ddr_cs_n<=0;ddr_act_n<=1;ddr_ras_n<=1;ddr_cas_n<=0;ddr_we_n<=0;ddr_bg<=map_bg;ddr_ba<=map_ba;ddr_a<=DDR_ADDR_W'(map_col);phy_wr_enable<=1;cache_write_valid<=1;cache_write_addr<=cur_req.addr;cache_write_data<=cur_req.wdata;wait_cnt<=1;state<=S_WWAIT;end
        S_WWAIT:if(wait_cnt==0)state<=S_RESP;
        S_RD:begin ddr_cs_n<=0;ddr_act_n<=1;ddr_ras_n<=1;ddr_cas_n<=0;ddr_we_n<=1;ddr_bg<=map_bg;ddr_ba<=map_ba;ddr_a<=DDR_ADDR_W'(map_col);wait_cnt<=T_CL_CK;state<=S_RLAT;end
        S_RLAT:if(wait_cnt==0)begin phy_rd_capture<=1;state<=S_RCAP;end
        S_RCAP:begin
          phy_rd_capture<=1;
          if(phy_rd_valid)begin phy_rd_capture<=0;rsp_rdata<=phy_rd_data;cache_write_valid<=1;cache_write_addr<=cur_req.addr;cache_write_data<=phy_rd_data;state<=S_RESP;end
        end
        S_RESP:begin
          if(!rsp_full)begin rsp_wr<=1;state<=S_IDLE;end
        end
        default:state<=S_RESET;
      endcase
    end
  end
endmodule
