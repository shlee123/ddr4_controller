// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module tb_ddr4_controller_m20;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;

  logic b_start,b_accept,b_active,b_last,b_unsup;
  logic [31:0] b_addr;
  logic [7:0] b_idx;
  ddr4_axi_burst_engine u_burst(.clk,.rst_n,.start(b_start),.start_addr(32'h1000),.burst_len(8'd3),.burst_size(3'd2),.burst_type(2'b01),.beat_accept(b_accept),.active(b_active),.beat_addr(b_addr),.beat_index(b_idx),.beat_last(b_last),.unsupported(b_unsup));

  logic q_push,q_pop,q_empty,q_full,q_ov,q_un;
  logic [63:0] q_in,q_out;
  logic [3:0] q_level;
  ddr4_rw_buffer #(.WIDTH(64),.DEPTH(8)) u_buf(.clk,.rst_n,.push(q_push),.push_data(q_in),.pop(q_pop),.pop_data(q_out),.empty(q_empty),.full(q_full),.level(q_level),.overflow(q_ov),.underflow(q_un));

  logic [3:0] req_valid,req_write;
  logic [3:0] req_bank[0:3];
  logic [14:0] req_row[0:3];
  logic [15:0] open_valid;
  logic [14:0] open_row[0:15];
  logic prefer_writes,g_accept,g_valid,g_hit,g_write;
  logic [1:0] g_index;
  logic [3:0] g_bank;
  ddr4_scheduler_v2 #(.ENTRIES(4),.BANK_W(4),.ROW_W(15),.AGE_W(4)) u_sched(.clk,.rst_n,.req_valid,.req_write,.req_bank,.req_row,.open_valid,.open_row,.prefer_writes,.grant_accept(g_accept),.grant_valid(g_valid),.grant_index(g_index),.grant_row_hit(g_hit),.grant_write(g_write),.grant_bank(g_bank));

  logic t_rd,t_wr,t_pre,t_mrs,t_zq,same_bg,t_allow_rd,t_allow_wr,t_allow_pre,t_allow_mrs,t_allow_zq,t_violation;
  ddr4_timing_ext #(.T_WTR(2),.T_RTP(2),.T_WR(3),.T_CCD_L(3),.T_CCD_S(2),.T_MOD(4),.T_MRD(2),.T_ZQCS(5)) u_time(.clk,.rst_n,.issue_rd(t_rd),.issue_wr(t_wr),.issue_pre(t_pre),.issue_mrs(t_mrs),.issue_zqcs(t_zq),.same_bank_group(same_bg),.allow_rd(t_allow_rd),.allow_wr(t_allow_wr),.allow_pre(t_allow_pre),.allow_mrs(t_allow_mrs),.allow_zqcs(t_allow_zq),.violation(t_violation));

  logic cfg_we,pd_enter,sr_enter,wake,data_valid,inject_error;
  logic [2:0] cfg_idx;
  logic [16:0] cfg_data,mr[0:6];
  logic [31:0] data_in;
  logic [7:0] crc_in;
  logic power_down,self_refresh,crc_error,poison,retry_req;
  ddr4_mode_power_error u_mpe(.clk,.rst_n,.cfg_we,.cfg_mr_index(cfg_idx),.cfg_mr_data(cfg_data),.enter_power_down(pd_enter),.enter_self_refresh(sr_enter),.wake,.data_valid,.data_in,.crc_in,.inject_error,.mr,.power_down,.self_refresh,.crc_error,.poison,.retry_req);

  logic p_req,p_rsp,p_rd,p_wr,p_ref,p_hit;
  logic [31:0] cycles,busy_cycles,read_count,write_count,refresh_count,row_hit_count,latency_sum,max_queue_level;
  ddr4_perf_monitor #(.QUEUE_W(4)) u_perf(.clk,.rst_n,.req_accept(p_req),.rsp_complete(p_rsp),.cmd_rd(p_rd),.cmd_wr(p_wr),.cmd_ref(p_ref),.row_hit(p_hit),.queue_level(q_level),.cycles,.busy_cycles,.read_count,.write_count,.refresh_count,.row_hit_count,.latency_sum,.max_queue_level);

  integer i;
  initial begin
    b_start=0;b_accept=0;q_push=0;q_pop=0;q_in=0;
    req_valid=0;req_write=0;open_valid=0;prefer_writes=0;g_accept=0;
    t_rd=0;t_wr=0;t_pre=0;t_mrs=0;t_zq=0;same_bg=0;
    cfg_we=0;cfg_idx=0;cfg_data=0;pd_enter=0;sr_enter=0;wake=0;data_valid=0;data_in=0;crc_in=0;inject_error=0;
    p_req=0;p_rsp=0;p_rd=0;p_wr=0;p_ref=0;p_hit=0;
    for(i=0;i<4;i=i+1) begin req_bank[i]=i; req_row[i]=i; end
    for(i=0;i<16;i=i+1) open_row[i]=0;
    repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

    @(negedge clk); b_start=1; @(negedge clk); b_start=0;
    for(i=0;i<4;i=i+1) begin
      if(!b_active || b_addr != 32'h1000+i*4 || b_idx != i) $fatal(1,"M11 burst mismatch beat=%0d addr=%h idx=%0d",i,b_addr,b_idx);
      @(negedge clk); b_accept=1; @(negedge clk); b_accept=0;
    end
    if(b_active || b_unsup) $fatal(1,"M11 burst completion failed");

    for(i=0;i<3;i=i+1) begin
      q_in=64'h100+i; @(negedge clk); q_push=1; @(negedge clk); q_push=0;
    end
    if(q_level!=3) $fatal(1,"M12 write buffer level=%0d",q_level);
    for(i=0;i<3;i=i+1) begin
      if(q_out!=64'h100+i) $fatal(1,"M13 read buffer order expected=%h got=%h",64'h100+i,q_out);
      @(negedge clk); q_pop=1; @(negedge clk); q_pop=0;
    end
    if(!q_empty || q_ov || q_un) $fatal(1,"M12/M13 buffer flags invalid");

    open_valid[2]=1; open_row[2]=15'h123;
    req_valid=4'b0011; req_bank[0]=1;req_row[0]=15'h001;req_write[0]=0;
    req_bank[1]=2;req_row[1]=15'h123;req_write[1]=1;prefer_writes=1;
    repeat(2) @(posedge clk);
    if(!g_valid || g_index!=1 || !g_hit || !g_write || g_bank!=2) $fatal(1,"M14/M15 scheduler priority failed");
    @(negedge clk);g_accept=1;@(negedge clk);g_accept=0;req_valid=0;

    same_bg=0;
    @(negedge clk);t_wr=1;@(negedge clk);t_wr=0;
    while(!t_allow_rd) @(posedge clk);
    @(negedge clk);t_rd=1;@(negedge clk);t_rd=0;
    while(!t_allow_pre) @(posedge clk);
    @(negedge clk);t_pre=1;@(negedge clk);t_pre=0;
    while(!t_allow_mrs) @(posedge clk);
    @(negedge clk);t_mrs=1;@(negedge clk);t_mrs=0;
    while(!t_allow_zq) @(posedge clk);
    @(negedge clk);t_zq=1;@(negedge clk);t_zq=0;
    if(t_violation) $fatal(1,"M16 legal timing sequence violated");

    cfg_idx=3;cfg_data=17'h15555;@(negedge clk);cfg_we=1;@(negedge clk);cfg_we=0;#1;
    if(mr[3]!=17'h15555) $fatal(1,"M17 MR programming failed");

    @(negedge clk);pd_enter=1;@(negedge clk);pd_enter=0;
    if(!power_down)$fatal(1,"M18 power-down failed");
    @(negedge clk);wake=1;@(negedge clk);wake=0;
    if(power_down)$fatal(1,"M18 wake failed");
    @(negedge clk);sr_enter=1;@(negedge clk);sr_enter=0;
    if(!self_refresh)$fatal(1,"M18 self-refresh failed");
    @(negedge clk);wake=1;@(negedge clk);wake=0;
    if(self_refresh)$fatal(1,"M18 self-refresh exit failed");

    data_in=32'hdeadbeef;crc_in=0;inject_error=1;
    @(negedge clk);data_valid=1;@(negedge clk);data_valid=0;#1;
    if(!poison) $fatal(1,"M19 poison missing");
    inject_error=0;

    @(negedge clk);p_req=1;p_rd=1;p_hit=1;@(negedge clk);p_req=0;p_rd=0;p_hit=0;
    repeat(3) @(posedge clk);
    @(negedge clk);p_rsp=1;p_wr=1;p_ref=1;@(negedge clk);p_rsp=0;p_wr=0;p_ref=0;
    repeat(2) @(posedge clk);
    if(read_count<1 || write_count<1 || refresh_count<1 || row_hit_count<1 || latency_sum<1 || busy_cycles<2) $fatal(1,"M20 counters incomplete");

    $display("PASS M11 AXI burst engine");
    $display("PASS M12 write buffer");
    $display("PASS M13 read buffer");
    $display("PASS M14 scheduler v2");
    $display("PASS M15 multi-bank optimization");
    $display("PASS M16 extended DDR4 timing");
    $display("PASS M17 mode registers");
    $display("PASS M18 power management");
    $display("PASS M19 error detection");
    $display("PASS M20 performance monitor");
    $finish;
  end

  initial begin #300000; $fatal(1,"M20 regression timeout"); end
endmodule
