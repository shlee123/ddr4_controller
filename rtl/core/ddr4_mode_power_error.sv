// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module ddr4_mode_power_error(
  input  logic clk,
  input  logic rst_n,
  input  logic cfg_we,
  input  logic [2:0] cfg_mr_index,
  input  logic [16:0] cfg_mr_data,
  input  logic enter_power_down,
  input  logic enter_self_refresh,
  input  logic wake,
  input  logic data_valid,
  input  logic [31:0] data_in,
  input  logic [7:0] crc_in,
  input  logic inject_error,
  output logic [16:0] mr [0:6],
  output logic power_down,
  output logic self_refresh,
  output logic crc_error,
  output logic poison,
  output logic retry_req
);
  integer i;
  logic [7:0] crc_calc;

  function automatic [7:0] calc_crc8(input logic [31:0] d);
    integer k;
    logic [7:0] c;
    begin
      c = 8'h00;
      for (k = 0; k < 32; k = k + 1)
        c = {c[6:0],1'b0} ^ ((c[7] ^ d[k]) ? 8'h07 : 8'h00);
      calc_crc8 = c;
    end
  endfunction

  always_comb crc_calc = calc_crc8(data_in);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 7; i = i + 1) mr[i] <= i[16:0];
      power_down <= 1'b0;
      self_refresh <= 1'b0;
      crc_error <= 1'b0;
      poison <= 1'b0;
      retry_req <= 1'b0;
    end else begin
      crc_error <= 1'b0;
      retry_req <= 1'b0;
      if (cfg_we && cfg_mr_index < 7) mr[cfg_mr_index] <= cfg_mr_data;
      if (wake) begin power_down <= 1'b0; self_refresh <= 1'b0; end
      else if (enter_self_refresh) self_refresh <= 1'b1;
      else if (enter_power_down) power_down <= 1'b1;
      if (data_valid && ((crc_calc != crc_in) || inject_error)) begin
        crc_error <= 1'b1;
        poison <= 1'b1;
        retry_req <= 1'b1;
      end
      if (data_valid && (crc_calc == crc_in) && !inject_error) poison <= 1'b0;
    end
  end
endmodule
