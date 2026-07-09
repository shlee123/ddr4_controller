`timescale 1ns/1ps
module ddr4_ctrl_tb;
  import ddr4_pkg::*;
  logic aclk=0, aresetn=0;
  logic ddr_clk=0, ddr_resetn=0;
  always #2.5 aclk = ~aclk;     // 200MHz AXI/APB domain
  always #1.0 ddr_clk = ~ddr_clk; // 500MHz DRAM/controller domain

  logic [31:0] awaddr, wdata, araddr; logic [7:0] awlen, arlen; logic [1:0] awburst, arburst;
  logic awvalid, awready, wvalid, wready, wlast, bvalid, bready; logic [3:0] wstrb; logic [1:0] bresp;
  logic arvalid, arready, rvalid, rready, rlast; logic [31:0] rdata; logic [1:0] rresp;
  logic psel,penable,pwrite; logic [31:0] paddr,pwdata,prdata; logic pready,pslverr;
  logic reset_n,ck_t,ck_c,cke,cs_n,act_n,ras_n,cas_n,we_n,odt,alert_n; logic [16:0] a; logic [1:0] ba,bg; wire [15:0] dq; wire [1:0] dqs_t,dqs_c; logic [1:0] dm_n;

  ddr4_ctrl_top dut(.*,
    .s_axi_awaddr(awaddr),.s_axi_awlen(awlen),.s_axi_awburst(awburst),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_araddr(araddr),.s_axi_arlen(arlen),.s_axi_arburst(arburst),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .ddr4_reset_n(reset_n),.ddr4_ck_t(ck_t),.ddr4_ck_c(ck_c),.ddr4_cke(cke),.ddr4_cs_n(cs_n),.ddr4_act_n(act_n),.ddr4_ras_n(ras_n),.ddr4_cas_n(cas_n),.ddr4_we_n(we_n),.ddr4_a(a),.ddr4_ba(ba),.ddr4_bg(bg),.ddr4_odt(odt),.ddr4_dq(dq),.ddr4_dqs_t(dqs_t),.ddr4_dqs_c(dqs_c),.ddr4_dm_n(dm_n),.ddr4_alert_n(alert_n));

  ddr4_sdram_model u_mem(.reset_n(reset_n),.ck_t(ck_t),.ck_c(ck_c),.cke(cke),.cs_n(cs_n),.act_n(act_n),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),.a(a),.ba(ba),.bg(bg),.odt(odt),.dq(dq),.dqs_t(dqs_t),.dqs_c(dqs_c),.dm_n(dm_n),.alert_n(alert_n));

  task automatic axi_write(input logic [31:0] addr,input logic [31:0] data);
    begin
      @(posedge aclk); awaddr<=addr; awlen<=0; awburst<=1; awvalid<=1; wdata<=data; wstrb<=4'hf; wlast<=1; wvalid<=1; bready<=1;
      while(!(awready && wready)) @(posedge aclk);
      @(posedge aclk); awvalid<=0; wvalid<=0;
      while(!bvalid) @(posedge aclk);
      @(posedge aclk); bready<=0;
    end
  endtask
  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      @(posedge aclk); araddr<=addr; arlen<=0; arburst<=1; arvalid<=1; rready<=1;
      while(!arready) @(posedge aclk);
      @(posedge aclk); arvalid<=0;
      while(!rvalid) @(posedge aclk);
      data=rdata; @(posedge aclk); rready<=0;
    end
  endtask

  int errors=0;
  initial begin
    $fsdbDumpfile("ddr4_ctrl_v2_1.fsdb");
    $fsdbDumpvars(0, ddr4_ctrl_tb);
    awaddr=0;awlen=0;awburst=0;awvalid=0;wdata=0;wstrb=0;wlast=0;wvalid=0;bready=0;araddr=0;arlen=0;arburst=0;arvalid=0;rready=0;
    psel=0;penable=0;pwrite=0;paddr=0;pwdata=0;
    repeat(10) @(posedge aclk); aresetn=1;
    repeat(5) @(posedge ddr_clk); ddr_resetn=1;
    repeat(200) @(posedge aclk);
    for(int i=0;i<64;i++) begin
      logic [31:0] addr,wd,rd; addr = {$urandom}%4096; addr[1:0]=2'b00; wd=$urandom;
      axi_write(addr,wd); axi_read(addr,rd);
      if(rd !== wd) begin $display("ERROR addr=%08x wr=%08x rd=%08x",addr,wd,rd); errors++; end
    end
    if(errors==0) $display("DDR4_CTRL_V2_1_RANDOM_TEST_PASS"); else $display("DDR4_CTRL_V2_1_RANDOM_TEST_FAIL errors=%0d",errors);
    #100 $finish;
  end
endmodule
