// SPDX-License-Identifier: MIT
// Xilinx/Vivado DDR differential clock output.
//
// This module is compiled only for FPGA builds. ODDR launches the clock from
// a dedicated DDR output register and OBUFDS drives the differential pins.

`timescale 1ns/1ps

module ddr4_fpga_clockgen (
  input  wire clk_in,
  output wire ddr_clk_t,
  output wire ddr_clk_c
);

  wire ddr_clk_oddr;

  ODDR #(
    .DDR_CLK_EDGE ("SAME_EDGE"),
    .INIT         (1'b0),
    .SRTYPE       ("SYNC")
  ) u_ddr_clk_oddr (
    .Q  (ddr_clk_oddr),
    .C  (clk_in),
    .CE (1'b1),
    .D1 (1'b1),
    .D2 (1'b0),
    .R  (1'b0),
    .S  (1'b0)
  );

  OBUFDS u_ddr_clk_obufds (
    .I  (ddr_clk_oddr),
    .O  (ddr_clk_t),
    .OB (ddr_clk_c)
  );

endmodule : ddr4_fpga_clockgen
