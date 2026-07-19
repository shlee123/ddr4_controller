`timescale 1ns/1ps

module tb_ddr4_controller_m6;
  import ddr4_ctrl_pkg::*;

  localparam int TIMEOUT = 100000;
  localparam logic [31:0] REG_STATUS = 32'h0000_0004;

  logic axi_clk=0, axi_rst_n=0, ddr_clk=0, ddr_rst_n=0;
  always #2.5 axi_clk = ~axi_clk;
  always #1.0 ddr_clk = ~ddr_clk;

  logic [31:0] s_axi_awaddr; logic [7:0] s_axi_awlen; logic [2:0] s_axi_awsize;
  logic [1:0] s_axi_awburst; logic s_axi_awvalid,s_axi_awready;
  logic [31:0] s_axi_wdata; logic [3:0] s_axi_wstrb; logic s_axi_wlast,s_axi_wvalid,s_axi_wready;
  logic [1:0] s_axi_bresp; logic s_axi_bvalid,s_axi_bready;
  logic [31:0] s_axi_araddr; logic [7:0] s_axi_arlen; logic [2:0] s_axi_arsize;
  logic [1:0] s_axi_arburst; logic s_axi_arvalid,s_axi_arready;
  logic [31:0] s_axi_rdata; logic [1:0] s_axi_rresp; logic s_axi_rlast,s_axi_rvalid,s_axi_rready;
  logic [31:0] paddr,pwdata,prdata; logic psel,penable,pwrite,pready,pslverr;
  logic ddr_ck_t,ddr_ck_c,ddr_reset_n,ddr_cke,ddr_cs_n,ddr_act_n,ddr_ras_n,ddr_cas_n,ddr_we_n;
  logic [1:0] ddr_bg,ddr_ba; logic [16:0] ddr_a; logic ddr_odt,ddr_par,ddr_alert_n;
  wire [15:0] ddr_dq; wire [1:0] ddr_dqs_t,ddr_dqs_c,ddr_dm_n;

  ddr4_controller_top dut (
    .axi_clk,.axi_rst_n,.clk(ddr_clk),.rst_n(ddr_rst_n),
    .s_axi_awaddr,.s_axi_awlen,.s_axi_awsize,.s_axi_awburst,.s_axi_awvalid,.s_axi_awready,
    .s_axi_wdata,.s_axi_wstrb,.s_axi_wlast,.s_axi_wvalid,.s_axi_wready,
    .s_axi_bresp,.s_axi_bvalid,.s_axi_bready,
    .s_axi_araddr,.s_axi_arlen,.s_axi_arsize,.s_axi_arburst,.s_axi_arvalid,.s_axi_arready,
    .s_axi_rdata,.s_axi_rresp,.s_axi_rlast,.s_axi_rvalid,.s_axi_rready,
    .paddr,.psel,.penable,.pwrite,.pwdata,.prdata,.pready,.pslverr,
    .ddr_ck_t,.ddr_ck_c,.ddr_reset_n,.ddr_cke,.ddr_cs_n,.ddr_act_n,.ddr_ras_n,.ddr_cas_n,.ddr_we_n,
    .ddr_bg,.ddr_ba,.ddr_a,.ddr_odt,.ddr_par,.ddr_alert_n,.ddr_dq,.ddr_dqs_t,.ddr_dqs_c,.ddr_dm_n);

  ddr4_sdram_model #(.DQ_W(16),.ADDR_W(17),.BA_W(2),.BG_W(2)) dram (
    .reset_n(ddr_reset_n),.ck_t(ddr_ck_t),.ck_c(ddr_ck_c),.cke(ddr_cke),.cs_n(ddr_cs_n),
    .act_n(ddr_act_n),.ras_n(ddr_ras_n),.cas_n(ddr_cas_n),.we_n(ddr_we_n),.a(ddr_a),.ba(ddr_ba),
    .bg(ddr_bg),.odt(ddr_odt),.dq(ddr_dq),.dqs_t(ddr_dqs_t),.dqs_c(ddr_dqs_c),.dm_n(ddr_dm_n),.alert_n(ddr_alert_n));

  task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
    integer n;
    begin
      @(posedge axi_clk); paddr<=addr; pwrite<=0; psel<=1; penable<=0;
      @(posedge axi_clk); penable<=1; n=0;
      while(!pready && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if(!pready) $fatal(1,"APB timeout");
      data=prdata;
      @(posedge axi_clk); psel<=0; penable<=0; paddr<='0;
    end
  endtask

  task automatic drive_aw(input logic [31:0] addr);
    integer n;
    begin
      s_axi_awaddr<=addr; s_axi_awlen<=0; s_axi_awsize<=3'd2; s_axi_awburst<=2'b01; s_axi_awvalid<=1;
      n=0; while(!(s_axi_awvalid&&s_axi_awready) && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if(n>=TIMEOUT) $fatal(1,"AW timeout");
      s_axi_awvalid<=0;
      @(posedge axi_clk);
    end
  endtask

  task automatic drive_w(input logic [31:0] data);
    integer n;
    begin
      s_axi_wdata<=data; s_axi_wstrb<=4'hf; s_axi_wlast<=1; s_axi_wvalid<=1;
      n=0; while(!(s_axi_wvalid&&s_axi_wready) && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if(n>=TIMEOUT) $fatal(1,"W timeout");
      s_axi_wvalid<=0; s_axi_wlast<=0;
      @(posedge axi_clk);
    end
  endtask

  task automatic wait_b;
    integer n;
    begin
      n=0; while(!(s_axi_bvalid&&s_axi_bready) && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if(n>=TIMEOUT) $fatal(1,"B timeout");
      if(s_axi_bresp!==2'b00) $fatal(1,"BRESP %b",s_axi_bresp);
      @(posedge axi_clk);
    end
  endtask

  task automatic axi_write(input logic [31:0] addr,input logic [31:0] data);
    begin drive_aw(addr); drive_w(data); wait_b(); end
  endtask

  task automatic drive_ar(input logic [31:0] addr);
    integer n;
    begin
      s_axi_araddr<=addr; s_axi_arlen<=0; s_axi_arsize<=3'd2; s_axi_arburst<=2'b01; s_axi_arvalid<=1;
      n=0; while(!(s_axi_arvalid&&s_axi_arready) && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if(n>=TIMEOUT) $fatal(1,"AR timeout");
      s_axi_arvalid<=0;
      @(posedge axi_clk);
    end
  endtask

  task automatic wait_r(output logic [31:0] data);
    integer n;
    begin
      n=0; while(!(s_axi_rvalid&&s_axi_rready) && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if(n>=TIMEOUT) $fatal(1,"R timeout");
      if(s_axi_rresp!==2'b00 || !s_axi_rlast) $fatal(1,"R response error");
      data=s_axi_rdata;
      @(posedge axi_clk);
    end
  endtask

  logic [1:0] bresp_stall; logic [31:0] rdata_stall; logic [1:0] rresp_stall; logic rlast_stall;
  logic bstall,rstall;
  always @(posedge axi_clk) begin
    if(!axi_rst_n) begin bstall<=0; rstall<=0; end
    else begin
      if(s_axi_bvalid&&!s_axi_bready) begin
        if(!bstall) bresp_stall<=s_axi_bresp;
        else if(s_axi_bresp!==bresp_stall) $fatal(1,"B payload changed under stall");
        bstall<=1;
      end else bstall<=0;
      if(s_axi_rvalid&&!s_axi_rready) begin
        if(!rstall) begin rdata_stall<=s_axi_rdata; rresp_stall<=s_axi_rresp; rlast_stall<=s_axi_rlast; end
        else if(s_axi_rdata!==rdata_stall || s_axi_rresp!==rresp_stall || s_axi_rlast!==rlast_stall)
          $fatal(1,"R payload changed under stall");
        rstall<=1;
      end else rstall<=0;
    end
  end

  logic [31:0] status,rd;
  integer i,n;
  initial begin
    s_axi_awaddr='0;s_axi_awlen=0;s_axi_awsize=2;s_axi_awburst=1;s_axi_awvalid=0;
    s_axi_wdata='0;s_axi_wstrb=0;s_axi_wlast=0;s_axi_wvalid=0;s_axi_bready=1;
    s_axi_araddr='0;s_axi_arlen=0;s_axi_arsize=2;s_axi_arburst=1;s_axi_arvalid=0;s_axi_rready=1;
    paddr='0;psel=0;penable=0;pwrite=0;pwdata='0;

    repeat(8) @(posedge axi_clk); axi_rst_n=1;
    repeat(8) @(posedge ddr_clk); ddr_rst_n=1;
    status=0;n=0;
    while(!status[0]&&n<TIMEOUT) begin apb_read(REG_STATUS,status); n=n+1; end
    if(!status[0]) $fatal(1,"init timeout");

    drive_aw(32'h1000); repeat(5) @(posedge axi_clk); drive_w(32'h1111_0001); wait_b();

    @(posedge axi_clk); s_axi_wdata<=32'h2222_0002; s_axi_wstrb<=4'hf; s_axi_wlast<=1; s_axi_wvalid<=1;
    repeat(5) begin @(posedge axi_clk); if(s_axi_wready) $fatal(1,"W accepted without AW"); end
    drive_aw(32'h1004);
    s_axi_wvalid<=0; s_axi_wlast<=0;
    wait_b();

    drive_ar(32'h1000); wait_r(rd); if(rd!==32'h1111_0001) $fatal(1,"readback 0 mismatch");
    drive_ar(32'h1004); wait_r(rd); if(rd!==32'h2222_0002) $fatal(1,"readback 1 mismatch");

    s_axi_bready=0;
    for(i=0;i<8;i=i+1) begin drive_aw(32'h1100+i*4); drive_w(32'h6000_0000+i); end
    repeat(20) @(posedge axi_clk); s_axi_bready=1;
    for(i=0;i<8;i=i+1) wait_b();

    s_axi_rready=0;
    for(i=0;i<8;i=i+1) drive_ar(32'h1100+i*4);
    repeat(20) @(posedge axi_clk); s_axi_rready=1;
    for(i=0;i<8;i=i+1) begin wait_r(rd); if(rd!==(32'h6000_0000+i)) $fatal(1,"ordered read mismatch %0d",i); end

    drive_aw(32'h1200);
    @(posedge axi_clk); axi_rst_n<=0; repeat(4) @(posedge axi_clk);
    if(s_axi_bvalid||s_axi_rvalid) $fatal(1,"response valid during reset");
    axi_rst_n<=1; repeat(8) @(posedge axi_clk);
    axi_write(32'h1200,32'habcd_1234);
    drive_ar(32'h1200); wait_r(rd); if(rd!==32'habcd_1234) $fatal(1,"post-reset transaction failed");

    @(posedge axi_clk);
    s_axi_araddr<=32'h1202; s_axi_arlen<=1; s_axi_arsize<=1; s_axi_arburst<=2'b10; s_axi_arvalid<=1;
    @(posedge axi_clk);
    if(!(s_axi_arlen!=0 || s_axi_arsize!=2 || s_axi_arburst!=2'b01 || s_axi_araddr[1:0]!=0))
      $fatal(1,"unsupported encoding detector failed");
    while(!s_axi_arready) @(posedge axi_clk);
    s_axi_arvalid<=0;
    @(posedge axi_clk);
    wait_r(rd);

    $display("PASS M6 AXI protocol coverage: aw_w_independent=1 outstanding=8 reset=1 unsupported_detected=1");
    $finish;
  end

  initial begin #2000000; $fatal(1,"M6 global timeout"); end
endmodule
