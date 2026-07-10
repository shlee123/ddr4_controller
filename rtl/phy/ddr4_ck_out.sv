// SPDX-License-Identifier: MIT
// Portable DDR CK/CK# output wrapper.
//
// Keep clock-output implementation isolated at the PHY/top boundary. FPGA or ASIC
// builds can replace this wrapper with ODDR/OSERDES/IOB or library clock cells
// without changing the controller or scheduler RTL.

`timescale 1ns/1ps

module ddr4_ck_out (
  input  logic clk,
  output logic ck_t,
  output logic ck_c
);

  assign ck_t = clk;
  assign ck_c = ~clk;

endmodule : ddr4_ck_out
