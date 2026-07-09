// SPDX-License-Identifier: MIT

`timescale 1ns/1ps

module tb_ddr4_controller;

  logic clk;
  logic rst_n;

  localparam int AXI_ADDR_W = 32;
  localparam int AXI_DATA_W = 32;
  localparam int APB_ADDR_W = 32;
  localparam int APB_DATA_W = 32;
  localparam int DDR_ADDR_W = 17;
  localparam int DDR_BG_W   = 2;
  localparam int DDR_BA_W   = 2;
  localparam int DDR_DQ_W   = 16;

  logic                     psel;
  logic                     penable;
  logic                     pwrite;
  logic [APB_ADDR_W-1:0]    paddr;
  logic [APB_DATA_W-1:0]    pwdata;
  logic [APB_DATA_W-1:0]    prdata;
  logic                     pready;
  logic                     pslverr;

  logic                     ddr_ck_t;
  logic                     ddr_ck_c;
  logic                     ddr_reset_n;
  logic                     ddr_cke;
  logic                     ddr_cs_n;
  logic                     ddr_act_n;
  logic                     ddr_ras_n;
  logic                     ddr_cas_n;
  logic                     ddr_we_n;
  logic [DDR_BG_W-1:0]      ddr_bg;
  logic [DDR_BA_W-1:0]      ddr_ba;
  logic [DDR_ADDR_W-1:0]    ddr_a;
  logic                     ddr_odt;
  logic                     ddr_par;
  logic                     ddr_alert_n;

  wire [DDR_DQ_W-1:0]       ddr_dq;
  wire [DDR_DQ_W/8-1:0]     ddr_dqs_t;
  wire [DDR_DQ_W/8-1:0]     ddr_dqs_c;
  wire [DDR_DQ_W/8-1:0]     ddr_dm_n;

  initial clk = 1'b0;
  always #1 clk = ~clk; // 500 MHz clock: 2 ns period

  task automatic apb_write(input logic [APB_ADDR_W-1:0] addr, input logic [APB_DATA_W-1:0] data);
    begin
      @(posedge clk);
      paddr   <= addr;
      pwdata  <= data;
      pwrite  <= 1'b1;
      psel    <= 1'b1;
      penable <= 1'b0;
      @(posedge clk);
      penable <= 1'b1;
      @(posedge clk);
      psel    <= 1'b0;
      penable <= 1'b0;
      pwrite  <= 1'b0;
    end
  endtask

  initial begin
    rst_n   = 1'b0;
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = '0;
    pwdata  = '0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    // Start controller initialization sequence through APB control register.
    apb_write(32'h0000_0000, 32'h0000_0001);

    repeat (300) @(posedge clk);
    $display("DDR4 controller + Micron 4Gb DDR4 model smoke simulation completed.");
    $finish;
  end

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W),
    .APB_DATA_W(APB_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W),
    .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W),
    .DDR_DQ_W(DDR_DQ_W)
  ) u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axi_awaddr  ('0),
    .s_axi_awlen   ('0),
    .s_axi_awsize  ('0),
    .s_axi_awburst ('0),
    .s_axi_awvalid (1'b0),
    .s_axi_awready (),
    .s_axi_wdata   ('0),
    .s_axi_wstrb   ('0),
    .s_axi_wlast   (1'b0),
    .s_axi_wvalid  (1'b0),
    .s_axi_wready  (),
    .s_axi_bresp   (),
    .s_axi_bvalid  (),
    .s_axi_bready  (1'b1),
    .s_axi_araddr  ('0),
    .s_axi_arlen   ('0),
    .s_axi_arsize  ('0),
    .s_axi_arburst ('0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (),
    .s_axi_rdata   (),
    .s_axi_rresp   (),
    .s_axi_rlast   (),
    .s_axi_rvalid  (),
    .s_axi_rready  (1'b1),
    .paddr         (paddr),
    .psel          (psel),
    .penable       (penable),
    .pwrite        (pwrite),
    .pwdata        (pwdata),
    .prdata        (prdata),
    .pready        (pready),
    .pslverr       (pslverr),
    .ddr_ck_t      (ddr_ck_t),
    .ddr_ck_c      (ddr_ck_c),
    .ddr_reset_n   (ddr_reset_n),
    .ddr_cke       (ddr_cke),
    .ddr_cs_n      (ddr_cs_n),
    .ddr_act_n     (ddr_act_n),
    .ddr_ras_n     (ddr_ras_n),
    .ddr_cas_n     (ddr_cas_n),
    .ddr_we_n      (ddr_we_n),
    .ddr_bg        (ddr_bg),
    .ddr_ba        (ddr_ba),
    .ddr_a         (ddr_a),
    .ddr_odt       (ddr_odt),
    .ddr_par       (ddr_par),
    .ddr_alert_n   (ddr_alert_n)
  );

  ddr4_sdram_model #(
    .ROW_W(15),
    .COL_W(10),
    .BANK_W(2),
    .BG_W(2),
    .DQ_W(16),
    .X16_MODE(1'b1)
  ) u_ddr4_model (
    .ck_t    (ddr_ck_t),
    .ck_c    (ddr_ck_c),
    .reset_n (ddr_reset_n),
    .cke     (ddr_cke),
    .cs_n    (ddr_cs_n),
    .act_n   (ddr_act_n),
    .ras_n   (ddr_ras_n),
    .cas_n   (ddr_cas_n),
    .we_n    (ddr_we_n),
    .bg      (ddr_bg),
    .ba      (ddr_ba),
    .a       (ddr_a),
    .odt     (ddr_odt),
    .par     (ddr_par),
    .alert_n (ddr_alert_n),
    .dq      (ddr_dq),
    .dqs_t   (ddr_dqs_t),
    .dqs_c   (ddr_dqs_c),
    .dm_n    (ddr_dm_n)
  );

endmodule : tb_ddr4_controller
