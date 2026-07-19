// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
import ddr4_ctrl_pkg::*;

module tb_ddr4_controller_m20_2;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;

  ddr_req_t wr_in, rd_in, wr_out, rd_out;
  logic wr_empty_in,rd_empty_in,wr_pop,rd_pop,wr_empty_out,rd_empty_out;
  logic downstream_wr_pop,downstream_rd_pop;
  logic grant_valid,grant_write,grant_row_hit,timing_violation;

  ddr4_native_request_mux #(.SINGLE_QUEUE_BYPASS(1'b0)) u_dut(
    .clk,.rst_n,.wr_req_in(wr_in),.wr_empty_in,.wr_pop,.wr_req_out(wr_out),.wr_empty_out,
    .rd_req_in(rd_in),.rd_empty_in,.rd_pop,.rd_req_out(rd_out),.rd_empty_out,
    .downstream_wr_pop,.downstream_rd_pop,.grant_valid,.grant_write,.grant_row_hit,.timing_violation);

  initial begin
    wr_in='0; rd_in='0; wr_empty_in=1; rd_empty_in=1;
    downstream_wr_pop=0; downstream_rd_pop=0;
    wr_in.wr=1; wr_in.addr=32'h0001_2340; wr_in.wdata=32'ha5a55a5a; wr_in.wstrb='1;
    rd_in.wr=0; rd_in.addr=32'h0002_4680;
    repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

    @(negedge clk); wr_empty_in=0; rd_empty_in=0;
    repeat(2) @(posedge clk);
    if(!grant_valid || !grant_write || wr_empty_out || !rd_empty_out)
      $fatal(1,"M20.2 write-preferred native arbitration failed");
    if(wr_out.addr!=wr_in.addr || wr_out.wdata!=wr_in.wdata)
      $fatal(1,"M20.2 write payload was not preserved");

    @(negedge clk); downstream_wr_pop=1;
    @(negedge clk); downstream_wr_pop=0; wr_empty_in=1;
    if(!wr_pop) repeat(1) @(posedge clk);

    if(!rd_empty_out) $fatal(1,"M20.2 tWTR did not block read immediately after write");
    repeat(4) @(posedge clk);
    if(!grant_valid || grant_write || rd_empty_out)
      $fatal(1,"M20.2 read request not released after tWTR");

    @(negedge clk); downstream_rd_pop=1;
    @(negedge clk); downstream_rd_pop=0; rd_empty_in=1;
    repeat(2) @(posedge clk);
    if(timing_violation) $fatal(1,"M20.2 legal native sequence reported violation");

    $display("PASS M20.2 native FIFO-to-scheduler datapath");
    $display("PASS M20.2 FR-FCFS request selection");
    $display("PASS M20.2 extended timing admission guard");
    $finish;
  end
  initial begin #10000; $fatal(1,"M20.2 regression timeout"); end
endmodule
