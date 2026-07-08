// SPDX-License-Identifier: MIT

`timescale 1ns/1ps

module tb_ddr4_controller;

  logic clk;
  logic rst_n;

  localparam int AXI_ADDR_W = 32;
  localparam int AXI_DATA_W = 32;
  localparam int APB_ADDR_W = 32;
  localparam int APB_DATA_W = 32;

  initial clk = 1'b0;
  always #1 clk = ~clk; // 500 MHz clock: 2 ns period

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (100) @(posedge clk);
    $display("DDR4 controller smoke simulation completed.");
    $finish;
  end

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W),
    .APB_DATA_W(APB_DATA_W)
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
    .paddr         ('0),
    .psel          (1'b0),
    .penable       (1'b0),
    .pwrite        (1'b0),
    .pwdata        ('0),
    .prdata        (),
    .pready        (),
    .pslverr       ()
  );

endmodule : tb_ddr4_controller
