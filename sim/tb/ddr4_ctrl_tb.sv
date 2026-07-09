`timescale 1ns/1ps
module ddr4_ctrl_tb;
  import ddr4_ctrl_pkg::*;

  logic axi_clk=0, axi_rst_n=0;
  logic clk=0, rst_n=0;
  always #2.5 axi_clk = ~axi_clk; // 200 MHz AXI/APB domain
  always #1.0 clk     = ~clk;     // 500 MHz DDR domain

  logic [31:0] s_axi_awaddr, s_axi_wdata, s_axi_araddr;
  logic [7:0]  s_axi_awlen, s_axi_arlen;
  logic [2:0]  s_axi_awsize, s_axi_arsize;
  logic [1:0]  s_axi_awburst, s_axi_arburst;
  logic        s_axi_awvalid, s_axi_awready;
  logic        s_axi_wvalid, s_axi_wready, s_axi_wlast;
  logic [3:0]  s_axi_wstrb;
  logic [1:0]  s_axi_bresp;
  logic        s_axi_bvalid, s_axi_bready;
  logic        s_axi_arvalid, s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0]  s_axi_rresp;
  logic        s_axi_rvalid, s_axi_rready, s_axi_rlast;

  logic [31:0] paddr, pwdata, prdata;
  logic psel, penable, pwrite, pready, pslverr;

  logic ddr_reset_n, ddr_ck_t, ddr_ck_c, ddr_cke, ddr_cs_n, ddr_act_n;
  logic ddr_ras_n, ddr_cas_n, ddr_we_n, ddr_odt, ddr_par, ddr_alert_n;
  logic [16:0] ddr_a;
  logic [1:0]  ddr_ba, ddr_bg;
  wire  [15:0] ddr_dq;
  wire  [1:0]  ddr_dqs_t, ddr_dqs_c, ddr_dm_n;

  ddr4_controller_top dut (
    .axi_clk(axi_clk), .axi_rst_n(axi_rst_n), .clk(clk), .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awlen(s_axi_awlen), .s_axi_awsize(s_axi_awsize), .s_axi_awburst(s_axi_awburst), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arlen(s_axi_arlen), .s_axi_arsize(s_axi_arsize), .s_axi_arburst(s_axi_arburst), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite), .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .ddr_ck_t(ddr_ck_t), .ddr_ck_c(ddr_ck_c), .ddr_reset_n(ddr_reset_n), .ddr_cke(ddr_cke), .ddr_cs_n(ddr_cs_n), .ddr_act_n(ddr_act_n),
    .ddr_ras_n(ddr_ras_n), .ddr_cas_n(ddr_cas_n), .ddr_we_n(ddr_we_n), .ddr_bg(ddr_bg), .ddr_ba(ddr_ba), .ddr_a(ddr_a),
    .ddr_odt(ddr_odt), .ddr_par(ddr_par), .ddr_alert_n(ddr_alert_n), .ddr_dq(ddr_dq), .ddr_dqs_t(ddr_dqs_t), .ddr_dqs_c(ddr_dqs_c), .ddr_dm_n(ddr_dm_n)
  );

  ddr4_sdram_model u_mem (
    .reset_n(ddr_reset_n), .ck_t(ddr_ck_t), .ck_c(ddr_ck_c), .cke(ddr_cke), .cs_n(ddr_cs_n), .act_n(ddr_act_n),
    .ras_n(ddr_ras_n), .cas_n(ddr_cas_n), .we_n(ddr_we_n), .a(ddr_a), .ba(ddr_ba), .bg(ddr_bg), .odt(ddr_odt),
    .dq(ddr_dq), .dqs_t(ddr_dqs_t), .dqs_c(ddr_dqs_c), .dm_n(ddr_dm_n), .alert_n(ddr_alert_n)
  );

  task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      @(posedge axi_clk);
      s_axi_awaddr  <= addr;
      s_axi_awlen   <= 8'd0;
      s_axi_awsize  <= 3'd2;
      s_axi_awburst <= 2'b01;
      s_axi_awvalid <= 1'b1;
      s_axi_wdata   <= data;
      s_axi_wstrb   <= 4'hf;
      s_axi_wlast   <= 1'b1;
      s_axi_wvalid  <= 1'b1;
      s_axi_bready  <= 1'b1;
      while (!(s_axi_awready && s_axi_wready)) @(posedge axi_clk);
      @(posedge axi_clk);
      s_axi_awvalid <= 1'b0;
      s_axi_wvalid  <= 1'b0;
      while (!s_axi_bvalid) @(posedge axi_clk);
      @(posedge axi_clk);
      s_axi_bready <= 1'b0;
    end
  endtask

  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      @(posedge axi_clk);
      s_axi_araddr  <= addr;
      s_axi_arlen   <= 8'd0;
      s_axi_arsize  <= 3'd2;
      s_axi_arburst <= 2'b01;
      s_axi_arvalid <= 1'b1;
      s_axi_rready  <= 1'b1;
      while (!s_axi_arready) @(posedge axi_clk);
      @(posedge axi_clk);
      s_axi_arvalid <= 1'b0;
      while (!s_axi_rvalid) @(posedge axi_clk);
      data = s_axi_rdata;
      @(posedge axi_clk);
      s_axi_rready <= 1'b0;
    end
  endtask

  int errors = 0;
  initial begin
    $fsdbDumpfile("ddr4_ctrl_v2_1.fsdb");
    $fsdbDumpvars(0, ddr4_ctrl_tb);

    s_axi_awaddr=0; s_axi_awlen=0; s_axi_awsize=0; s_axi_awburst=0; s_axi_awvalid=0;
    s_axi_wdata=0; s_axi_wstrb=0; s_axi_wlast=0; s_axi_wvalid=0; s_axi_bready=0;
    s_axi_araddr=0; s_axi_arlen=0; s_axi_arsize=0; s_axi_arburst=0; s_axi_arvalid=0; s_axi_rready=0;
    psel=0; penable=0; pwrite=0; paddr=0; pwdata=0;

    repeat(10) @(posedge axi_clk); axi_rst_n = 1'b1;
    repeat(10) @(posedge clk);     rst_n     = 1'b1;
    repeat(800) @(posedge axi_clk);

    for(int i=0;i<64;i++) begin
      logic [31:0] addr, wd, rd;
      addr = {$urandom}%4096;
      addr[1:0] = 2'b00;
      wd = $urandom;
      axi_write(addr, wd);
      axi_read(addr, rd);
      if (rd !== wd) begin
        $display("ERROR addr=%08x wr=%08x rd=%08x", addr, wd, rd);
        errors++;
      end
    end

    if(errors == 0) $display("DDR4_CONTROLLER_TOP_V2_1_RANDOM_TEST_PASS");
    else            $display("DDR4_CONTROLLER_TOP_V2_1_RANDOM_TEST_FAIL errors=%0d", errors);
    #100 $finish;
  end
endmodule
