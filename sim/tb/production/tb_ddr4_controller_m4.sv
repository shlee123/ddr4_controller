`timescale 1ns/1ps

module tb_ddr4_controller_m4;
  import ddr4_ctrl_pkg::*;

  localparam int AXI_ADDR_W=32, AXI_DATA_W=32, APB_ADDR_W=32, APB_DATA_W=32;
  localparam int DDR_ADDR_W=17, DDR_BG_W=2, DDR_BA_W=2, DDR_DQ_W=16, DDR_DM_W=2;
  localparam logic [31:0] REG_STATUS=32'h4;
  localparam int TIMEOUT=10000;

  logic axi_clk=0, axi_rst_n=0, ddr_clk=0, ddr_rst_n=0;
  always #2.5 axi_clk=~axi_clk;
  always #1.0 ddr_clk=~ddr_clk;

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

  ddr4_controller_top #(.AXI_ADDR_W(32),.AXI_DATA_W(32),.APB_ADDR_W(32),.APB_DATA_W(32),
    .DDR_ADDR_W(17),.DDR_BG_W(2),.DDR_BA_W(2),.DDR_DQ_W(16),.DDR_DM_W(2)) dut (
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
      while (!pready && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if (!pready) $fatal(1,"APB timeout");
      data=prdata;
      @(posedge axi_clk); psel<=0; penable<=0; paddr<='0;
    end
  endtask

  task automatic axi_write(input logic [31:0] addr,input logic [31:0] data);
    integer n;
    begin
      @(posedge axi_clk);
      s_axi_awaddr<=addr; s_axi_awlen<=0; s_axi_awsize<=3'd2; s_axi_awburst<=2'b01; s_axi_awvalid<=1;
      n=0; while (!s_axi_awready && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if (!s_axi_awready) $fatal(1,"AW timeout addr=%h",addr);
      @(posedge axi_clk); s_axi_awvalid<=0;
      s_axi_wdata<=data; s_axi_wstrb<=4'hf; s_axi_wlast<=1; s_axi_wvalid<=1;
      n=0; while (!s_axi_wready && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if (!s_axi_wready) $fatal(1,"W timeout addr=%h",addr);
      @(posedge axi_clk); s_axi_wvalid<=0; s_axi_wlast<=0;
      n=0; while (!s_axi_bvalid && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if (!s_axi_bvalid) $fatal(1,"B timeout addr=%h",addr);
      if (s_axi_bresp!==2'b00) $fatal(1,"BRESP error addr=%h resp=%b",addr,s_axi_bresp);
      @(posedge axi_clk);
    end
  endtask

  task automatic axi_read(input logic [31:0] addr,output logic [31:0] data);
    integer n;
    begin
      @(posedge axi_clk);
      s_axi_araddr<=addr; s_axi_arlen<=0; s_axi_arsize<=3'd2; s_axi_arburst<=2'b01; s_axi_arvalid<=1;
      n=0; while (!s_axi_arready && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if (!s_axi_arready) $fatal(1,"AR timeout addr=%h",addr);
      @(posedge axi_clk); s_axi_arvalid<=0;
      n=0; while (!s_axi_rvalid && n<TIMEOUT) begin @(posedge axi_clk); n=n+1; end
      if (!s_axi_rvalid) $fatal(1,"R timeout addr=%h",addr);
      if (s_axi_rresp!==2'b00) $fatal(1,"RRESP error addr=%h resp=%b",addr,s_axi_rresp);
      if (!s_axi_rlast) $fatal(1,"Missing RLAST addr=%h",addr);
      data=s_axi_rdata;
      @(posedge axi_clk);
    end
  endtask

  logic [31:0] status,rd;
  logic [31:0] sb_addr[0:3],sb_data[0:3];
  integer i,n;
  initial begin
    s_axi_awaddr='0;s_axi_awlen=0;s_axi_awsize=2;s_axi_awburst=1;s_axi_awvalid=0;
    s_axi_wdata='0;s_axi_wstrb=0;s_axi_wlast=0;s_axi_wvalid=0;s_axi_bready=1;
    s_axi_araddr='0;s_axi_arlen=0;s_axi_arsize=2;s_axi_arburst=1;s_axi_arvalid=0;s_axi_rready=1;
    paddr='0;psel=0;penable=0;pwrite=0;pwdata='0;
    sb_addr[0]=32'h0000_0100; sb_data[0]=32'h1122_3344;
    sb_addr[1]=32'h0000_0204; sb_data[1]=32'ha5a5_5a5a;
    sb_addr[2]=32'h0001_0308; sb_data[2]=32'hdead_beef;
    sb_addr[3]=32'h0080_040c; sb_data[3]=32'hc001_d00d;
    repeat(8) @(posedge axi_clk); axi_rst_n=1;
    repeat(8) @(posedge ddr_clk); ddr_rst_n=1;
    status=0;n=0;
    while(!status[0] && n<TIMEOUT) begin apb_read(REG_STATUS,status); n=n+1; end
    if(!status[0]) $fatal(1,"init_done timeout");
    for(i=0;i<4;i=i+1) axi_write(sb_addr[i],sb_data[i]);
    for(i=0;i<4;i=i+1) begin
      axi_read(sb_addr[i],rd);
      if(rd!==sb_data[i]) $fatal(1,"Scoreboard mismatch addr=%h expected=%h actual=%h",sb_addr[i],sb_data[i],rd);
    end
    $display("PASS M4 AXI single read/write scoreboard: transactions=%0d",8);
    $finish;
  end

  initial begin #250000; $fatal(1,"M4 global timeout"); end
endmodule
