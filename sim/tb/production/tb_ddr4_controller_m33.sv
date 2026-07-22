`timescale 1ns/1ps
import ddr4_ctrl_pkg::*;
module tb_ddr4_controller_m33;
  reg clk=0;always #5 clk=~clk;reg rst_n=0;
  reg[31:0]axi_addr;wire[9:0]col;wire[1:0]bank,bg;wire[14:0]row;
  ddr4_address_mapper u_map(.axi_addr(axi_addr),.col(col),.bank(bank),.bank_group(bg),.row(row));
  reg wr_enable;reg[31:0]wr_data;reg[3:0]wr_strb;wire[15:0]dq_out;wire[1:0]dm_n;wire dq_oe,dqs_oe;wire[1:0]dqs_t,dqs_c;
  reg rd_en;reg[15:0]dq_in;wire[31:0]rd_data;wire rd_valid;
  ddr4_x16_data_path u_dp(.clk,.rst_n,.wr_enable,.wr_data,.wr_strb,.dq_out,.dm_n_out(dm_n),.dq_oe,.dqs_oe,.dqs_t_out(dqs_t),.dqs_c_out(dqs_c),.rd_capture_enable(rd_en),.dq_in,.rd_data,.rd_data_valid(rd_valid));
  reg init_start=1;wire init_done;reg[16:0]mr[0:6];ddr_req_t wr_req_data,rd_req_data;reg wr_empty=1,rd_empty=1;wire wr_rd,rd_rd;ddr_rsp_t rsp_data;wire rsp_wr;reg rsp_full=0;
  wire[31:0]cache_lookup_addr;reg cache_hit=0;reg[31:0]cache_lookup_data=0;wire cache_write_valid;wire[31:0]cache_write_addr,cache_write_data;
  wire ddr_reset_n,ddr_cke,ddr_cs_n,ddr_act_n,ddr_ras_n,ddr_cas_n,ddr_we_n;wire[1:0]ddr_bg,ddr_ba;wire[16:0]ddr_a;wire ddr_odt,ddr_par;
  wire[15:0]s_dq_out;wire s_dq_oe;wire[1:0]s_dqs_t,s_dqs_c;wire s_dqs_oe;wire[1:0]s_dm;wire s_dm_oe;
  ddr4_scheduler_open_page u_sched(.clk,.rst_n,.init_start,.init_done,.mr,.wr_req_data,.wr_req_empty(wr_empty),.wr_req_rd(wr_rd),.rd_req_data,.rd_req_empty(rd_empty),.rd_req_rd(rd_rd),.rsp_data,.rsp_wr,.rsp_full,.cache_lookup_addr,.cache_hit,.cache_lookup_data,.cache_write_valid,.cache_write_addr,.cache_write_data,.ddr_reset_n,.ddr_cke,.ddr_cs_n,.ddr_act_n,.ddr_ras_n,.ddr_cas_n,.ddr_we_n,.ddr_bg,.ddr_ba,.ddr_a,.ddr_odt,.ddr_par,.ddr_dq_in(16'h0),.ddr_dq_out(s_dq_out),.ddr_dq_oe(s_dq_oe),.ddr_dqs_t_out(s_dqs_t),.ddr_dqs_c_out(s_dqs_c),.ddr_dqs_oe(s_dqs_oe),.ddr_dm_n_out(s_dm),.ddr_dm_oe(s_dm_oe));
  integer errors=0;integer act_count=0;integer pre_count=0;integer i;
  always @(posedge clk)begin if(!ddr_cs_n&&!ddr_act_n)act_count=act_count+1;if(!ddr_cs_n&&ddr_act_n&&!ddr_ras_n&&ddr_cas_n&&!ddr_we_n)pre_count=pre_count+1;end
  task send_write(input[31:0]a,input[31:0]d);begin @(negedge clk);wr_req_data='0;wr_req_data.wr=1;wr_req_data.addr=a;wr_req_data.wdata=d;wr_req_data.wstrb=4'hf;wr_empty=0;while(!wr_rd)@(negedge clk);@(negedge clk);wr_empty=1;while(!rsp_wr)@(negedge clk);end endtask
  initial begin
    for(i=0;i<7;i=i+1)mr[i]=0;wr_req_data='0;rd_req_data='0;wr_enable=0;wr_data=0;wr_strb=0;rd_en=0;dq_in=0;axi_addr=0;
    repeat(3)@(negedge clk);rst_n=1;
    axi_addr={1'b0,15'h1234,2'b10,2'b01,10'h155,2'b00};#1;
    if(row!==15'h1234||bg!==2'b10||bank!==2'b01||col!==10'h155)begin $display("ERROR address map");errors=errors+1;end
    wr_data=32'hA1B2_C3D4;wr_strb=4'b1011;wr_enable=1;#1;
    if(dq_out!==16'hC3D4||dm_n!==2'b00)begin $display("ERROR write rising half");errors=errors+1;end
    @(negedge clk);#1;if(dq_out!==16'hA1B2||dm_n!==2'b01)begin $display("ERROR write falling half");errors=errors+1;end
    wr_enable=0;rd_en=1;dq_in=16'h3344;@(negedge clk);dq_in=16'h1122;@(posedge clk);#1;
    if(!rd_valid||rd_data!==32'h1122_3344)begin $display("ERROR dual-edge read %h",rd_data);errors=errors+1;end rd_en=0;
    wait(init_done);send_write(32'h0012_3000,32'h11112222);send_write(32'h0012_3004,32'h33334444);
    if(act_count!==1||pre_count!==0)begin $display("ERROR open page act=%0d pre=%0d",act_count,pre_count);errors=errors+1;end
    if(errors==0)$display("PASS M33 AXI32-DQ16 mapping, address map, open-page and dual-edge read");else $display("FAIL M33 errors=%0d",errors);
    #20;$finish;
  end
endmodule
