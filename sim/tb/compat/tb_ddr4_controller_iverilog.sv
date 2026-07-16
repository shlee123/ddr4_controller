// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module tb_ddr4_controller;
  localparam integer AXI_ADDR_W = 32;
  localparam integer AXI_DATA_W = 32;
  localparam integer APB_ADDR_W = 32;
  localparam integer APB_DATA_W = 32;
  localparam integer DDR_ADDR_W = 17;
  localparam integer DDR_BG_W   = 2;
  localparam integer DDR_BA_W   = 2;
  localparam integer DDR_DQ_W   = 16;
  localparam integer DDR_DM_W   = DDR_DQ_W/8;

  reg clk;
  reg rst_n;

  reg  [AXI_ADDR_W-1:0] s_axi_awaddr;
  reg  [7:0]            s_axi_awlen;
  reg  [2:0]            s_axi_awsize;
  reg  [1:0]            s_axi_awburst;
  reg                   s_axi_awvalid;
  wire                  s_axi_awready;
  reg  [AXI_DATA_W-1:0] s_axi_wdata;
  reg  [AXI_DATA_W/8-1:0] s_axi_wstrb;
  reg                   s_axi_wlast;
  reg                   s_axi_wvalid;
  wire                  s_axi_wready;
  wire [1:0]            s_axi_bresp;
  wire                  s_axi_bvalid;
  reg                   s_axi_bready;

  reg  [AXI_ADDR_W-1:0] s_axi_araddr;
  reg  [7:0]            s_axi_arlen;
  reg  [2:0]            s_axi_arsize;
  reg  [1:0]            s_axi_arburst;
  reg                   s_axi_arvalid;
  wire                  s_axi_arready;
  wire [AXI_DATA_W-1:0] s_axi_rdata;
  wire [1:0]            s_axi_rresp;
  wire                  s_axi_rlast;
  wire                  s_axi_rvalid;
  reg                   s_axi_rready;

  reg  [APB_ADDR_W-1:0] paddr;
  reg                   psel;
  reg                   penable;
  reg                   pwrite;
  reg  [APB_DATA_W-1:0] pwdata;
  wire [APB_DATA_W-1:0] prdata;
  wire                  pready;
  wire                  pslverr;

  wire                  ddr_ck_t;
  wire                  ddr_ck_c;
  wire                  ddr_reset_n;
  wire                  ddr_cke;
  wire                  ddr_cs_n;
  wire                  ddr_act_n;
  wire                  ddr_ras_n;
  wire                  ddr_cas_n;
  wire                  ddr_we_n;
  wire [DDR_BG_W-1:0]   ddr_bg;
  wire [DDR_BA_W-1:0]   ddr_ba;
  wire [DDR_ADDR_W-1:0] ddr_a;
  wire                  ddr_odt;
  wire                  ddr_par;
  wire                  ddr_alert_n;
  wire [DDR_DQ_W-1:0]   ddr_dq;
  wire [DDR_DM_W-1:0]   ddr_dqs_t;
  wire [DDR_DM_W-1:0]   ddr_dqs_c;
  wire [DDR_DM_W-1:0]   ddr_dm_n;

  initial clk = 1'b0;
  always #1 clk = ~clk;

  task burst_read_check;
    input [AXI_ADDR_W-1:0] addr;
    input [7:0] len;
    input [2:0] size;
    input [1:0] burst;
    integer beat;
    integer timeout;
    begin
      beat = 0;
      timeout = 0;
      @(posedge clk);
      s_axi_araddr  <= addr;
      s_axi_arlen   <= len;
      s_axi_arsize  <= size;
      s_axi_arburst <= burst;
      s_axi_arvalid <= 1'b1;

      while (s_axi_arready !== 1'b1) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 2000) $fatal(1, "AXI AR timeout");
      end

      @(posedge clk);
      s_axi_arvalid <= 1'b0;
      timeout = 0;

      while (beat <= len) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 10000) $fatal(1, "AXI R timeout at beat %0d", beat);
        if (s_axi_rvalid && s_axi_rready) begin
          if (s_axi_rresp !== 2'b00)
            $fatal(1, "AXI RRESP error at beat %0d", beat);
          if (s_axi_rlast !== (beat == len))
            $fatal(1, "AXI RLAST mismatch at beat %0d", beat);
          $display("AXI beat %0d/%0d data=0x%08x last=%0b", beat, len, s_axi_rdata, s_axi_rlast);
          beat = beat + 1;
        end
      end
      $display("PASS burst addr=0x%08x beats=%0d type=%0b", addr, len+1, burst);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 0; s_axi_awburst = 0;
    s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wlast = 0;
    s_axi_wvalid = 0; s_axi_bready = 1;
    s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 0; s_axi_arburst = 0;
    s_axi_arvalid = 0; s_axi_rready = 1;
    paddr = 0; psel = 0; penable = 0; pwrite = 0; pwdata = 0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (100) @(posedge clk);

    burst_read_check(32'h0000_0000, 8'd3, 3'd2, 2'b01);
    burst_read_check(32'h0000_0040, 8'd3, 3'd2, 2'b00);
    burst_read_check(32'h0000_0038, 8'd3, 3'd2, 2'b10);

    $display("DDR4 controller AXI burst-read regression completed successfully");
    $finish;
  end

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W), .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W), .APB_DATA_W(APB_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W), .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W), .DDR_DQ_W(DDR_DQ_W)
  ) u_dut (
    .axi_clk(clk), .axi_rst_n(rst_n), .clk(clk), .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize), .s_axi_awburst(s_axi_awburst),
    .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast), .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize), .s_axi_arburst(s_axi_arburst),
    .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
    .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .ddr_ck_t(ddr_ck_t), .ddr_ck_c(ddr_ck_c), .ddr_reset_n(ddr_reset_n),
    .ddr_cke(ddr_cke), .ddr_cs_n(ddr_cs_n), .ddr_act_n(ddr_act_n),
    .ddr_ras_n(ddr_ras_n), .ddr_cas_n(ddr_cas_n), .ddr_we_n(ddr_we_n),
    .ddr_bg(ddr_bg), .ddr_ba(ddr_ba), .ddr_a(ddr_a), .ddr_odt(ddr_odt),
    .ddr_par(ddr_par), .ddr_alert_n(ddr_alert_n), .ddr_dq(ddr_dq),
    .ddr_dqs_t(ddr_dqs_t), .ddr_dqs_c(ddr_dqs_c), .ddr_dm_n(ddr_dm_n)
  );

  ddr4_sdram_model #(
    .DQ_W(DDR_DQ_W), .ADDR_W(DDR_ADDR_W), .BA_W(DDR_BA_W), .BG_W(DDR_BG_W)
  ) u_model (
    .reset_n(ddr_reset_n), .ck_t(ddr_ck_t), .ck_c(ddr_ck_c),
    .cke(ddr_cke), .cs_n(ddr_cs_n), .act_n(ddr_act_n),
    .ras_n(ddr_ras_n), .cas_n(ddr_cas_n), .we_n(ddr_we_n),
    .a(ddr_a), .ba(ddr_ba), .bg(ddr_bg), .odt(ddr_odt),
    .dq(ddr_dq), .dqs_t(ddr_dqs_t), .dqs_c(ddr_dqs_c),
    .dm_n(ddr_dm_n), .alert_n(ddr_alert_n)
  );
endmodule
