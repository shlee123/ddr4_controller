// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_ddr4_controller_m20_1;
  logic axi_clk=0,clk=0,axi_rst_n=0,rst_n=0;
  always #5 axi_clk=~axi_clk;
  always #2 clk=~clk;
  logic [31:0] awaddr,wdata,araddr,paddr,pwdata,prdata,rdata;
  logic [7:0] awlen,arlen; logic [2:0] awsize,arsize; logic [1:0] awburst,arburst;
  logic awvalid,awready,wlast,wvalid,wready,bvalid,bready,arvalid,arready,rlast,rvalid,rready;
  logic [3:0] wstrb; logic [1:0] bresp,rresp;
  logic psel,penable,pwrite,pready,pslverr;
  logic ck_t,ck_c,reset_n,cke,cs_n,act_n,ras_n,cas_n,we_n,odt,par;
  logic [1:0] bg,ba; logic [16:0] a; logic alert_n=1;
  wire [15:0] dq; wire [1:0] dqs_t,dqs_c,dm_n;
  logic [31:0] cycles,busy,reads,writes,refs,latency,maxq; logic burst_error;

  ddr4_controller_top_m20_1 dut(
    .axi_clk,.axi_rst_n,.clk,.rst_n,.s_axi_awaddr(awaddr),.s_axi_awlen(awlen),
    .s_axi_awsize(awsize),.s_axi_awburst(awburst),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_araddr(araddr),
    .s_axi_arlen(arlen),.s_axi_arsize(arsize),.s_axi_arburst(arburst),.s_axi_arvalid(arvalid),
    .s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),
    .s_axi_rvalid(rvalid),.s_axi_rready(rready),.paddr,.psel,.penable,.pwrite,.pwdata,.prdata,.pready,.pslverr,
    .ddr_ck_t(ck_t),.ddr_ck_c(ck_c),.ddr_reset_n(reset_n),.ddr_cke(cke),.ddr_cs_n(cs_n),
    .ddr_act_n(act_n),.ddr_ras_n(ras_n),.ddr_cas_n(cas_n),.ddr_we_n(we_n),.ddr_bg(bg),.ddr_ba(ba),
    .ddr_a(a),.ddr_odt(odt),.ddr_par(par),.ddr_alert_n(alert_n),.ddr_dq(dq),.ddr_dqs_t(dqs_t),
    .ddr_dqs_c(dqs_c),.ddr_dm_n(dm_n),.perf_cycles(cycles),.perf_busy_cycles(busy),
    .perf_read_count(reads),.perf_write_count(writes),.perf_refresh_count(refs),.perf_latency_sum(latency),
    .perf_max_queue_level(maxq),.burst_error);

  task automatic apb_read(input [31:0] addr, output [31:0] data);
    begin
      @(negedge axi_clk); paddr=addr;psel=1;penable=0;pwrite=0;
      @(negedge axi_clk); penable=1;
      @(posedge axi_clk); #1; data=prdata;
      @(negedge axi_clk); psel=0;penable=0;
    end
  endtask
  logic [31:0] rdval;
  initial begin
    awaddr=0;awlen=0;awsize=2;awburst=1;awvalid=0;wdata=0;wstrb='1;wlast=1;wvalid=0;bready=1;
    araddr=0;arlen=0;arsize=2;arburst=1;arvalid=0;rready=1;
    paddr=0;psel=0;penable=0;pwrite=0;pwdata=0;
    repeat(5) @(posedge axi_clk); axi_rst_n=1; rst_n=1;
    repeat(8) @(posedge axi_clk);
    if(cycles<4) $fatal(1,"M20.1 live performance clock integration failed");

    // Accepted illegal AXI burst must be observed by integrated burst engine.
    @(negedge axi_clk); awaddr=32'h1000;awlen=3;awsize=2;awburst=2'b11;awvalid=1;
    while(!awready) @(posedge axi_clk);
    @(negedge axi_clk); awvalid=0;
    repeat(2) @(posedge axi_clk);
    if(!burst_error) $fatal(1,"M20.1 burst error not connected to live AXI handshake");

    apb_read(32'h100,rdval);
    if(rdval==0 || rdval!=cycles) $fatal(1,"M20.1 APB performance register mismatch read=%0d live=%0d",rdval,cycles);
    apb_read(32'h11c,rdval);
    if(!rdval[0]) $fatal(1,"M20.1 APB burst status missing");

    $display("PASS M20.1 top-level production integration");
    $finish;
  end
  initial begin #200000; $fatal(1,"M20.1 timeout"); end
endmodule
