// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_x16_data_path #(
  parameter integer AXI_DATA_W = 32,
  parameter integer DQ_W = 16,
  parameter integer DM_W = DQ_W/8
)(
  input wire clk,input wire rst_n,
  input wire wr_enable,input wire[AXI_DATA_W-1:0]wr_data,input wire[AXI_DATA_W/8-1:0]wr_strb,
  output wire[DQ_W-1:0]dq_out,output wire[DM_W-1:0]dm_n_out,output wire dq_oe,output wire dqs_oe,
  output wire[DM_W-1:0]dqs_t_out,output wire[DM_W-1:0]dqs_c_out,
  input wire rd_capture_enable,input wire[DQ_W-1:0]dq_in,
  output reg[AXI_DATA_W-1:0]rd_data,output reg rd_data_valid
);
  reg[DQ_W-1:0] rd_first_edge;
  assign dq_out = clk ? wr_data[DQ_W-1:0] : wr_data[2*DQ_W-1:DQ_W];
  assign dm_n_out = clk ? ~wr_strb[DM_W-1:0] : ~wr_strb[2*DM_W-1:DM_W];
  assign dq_oe=wr_enable; assign dqs_oe=wr_enable;
  assign dqs_t_out={DM_W{clk}}; assign dqs_c_out={DM_W{~clk}};

  // Capture the first transfer on the falling edge and the second transfer on
  // the following rising edge. Both edges are therefore retained in rd_data.
  always @(negedge clk or negedge rst_n) begin
    if(!rst_n) rd_first_edge<={DQ_W{1'b0}};
    else if(rd_capture_enable) rd_first_edge<=dq_in;
  end
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin rd_data<={AXI_DATA_W{1'b0}};rd_data_valid<=1'b0;end
    else begin
      rd_data_valid<=1'b0;
      if(rd_capture_enable) begin rd_data<={dq_in,rd_first_edge};rd_data_valid<=1'b1;end
    end
  end
  initial begin
    if(AXI_DATA_W!=2*DQ_W)$error("AXI_DATA_W must equal 2*DQ_W");
    if((AXI_DATA_W/8)!=2*DM_W)$error("WSTRB width mismatch");
  end
endmodule
