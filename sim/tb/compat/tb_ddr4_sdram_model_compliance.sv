// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_ddr4_sdram_model_compliance;
  reg ck_t=0, reset_n=0, cke=0, cs_n=1, act_n=1;
  reg ras_n=1, cas_n=1, we_n=1, odt=0;
  reg [16:0] a=0;
  reg [1:0] ba=0, bg=0;
  wire [15:0] dq;
  wire [1:0] dqs_t,dqs_c,dm_n;
  wire alert_n;
  always #1 ck_t=~ck_t;

  ddr4_sdram_model #(.CL_CK(2)) dut(
    .reset_n,.ck_t,.ck_c(~ck_t),.cke,.cs_n,.act_n,.ras_n,.cas_n,.we_n,
    .a,.ba,.bg,.odt,.dq,.dqs_t,.dqs_c,.dm_n,.alert_n);

  task cmd;
    input i_act_n,i_ras_n,i_cas_n,i_we_n;
    input [1:0] i_bg,i_ba;
    input [16:0] i_a;
    begin
      @(negedge ck_t);
      cs_n=0; act_n=i_act_n; ras_n=i_ras_n; cas_n=i_cas_n; we_n=i_we_n;
      bg=i_bg; ba=i_ba; a=i_a;
      @(negedge ck_t);
      cs_n=1; act_n=1; ras_n=1; cas_n=1; we_n=1; bg=0; ba=0; a=0;
    end
  endtask

  initial begin
    repeat(3) @(posedge ck_t);
    reset_n=1; cke=1;

    // MRS is ACT_n=1 and RAS/CAS/WE=000; BG0/BA select MR0-MR6.
    cmd(1,0,0,0,2'b01,2'b10,17'h055aa);
    if(dut.mode_reg[6]!==16'h55aa) $fatal(1,"MRS decode/MR6 selection failed");

    // x16 has 2 bank groups. BG0=1, BA=2 maps to logical bank 6.
    cmd(0,1,1,1,2'b01,2'b10,17'h01234);
    if(!dut.bank_open[6] || dut.open_row[6]!==15'h1234)
      $fatal(1,"x16 BG0/BA/row mapping failed");

    // READ is 101 and must preserve every logical address bit.
    cmd(1,1,0,1,2'b01,2'b10,17'h002a5);
    if(dut.read_base!=={1'b1,2'b10,15'h1234,10'h2a5})
      $fatal(1,"full logical address mapping failed");

    // PRE is 010 and A10 selects PREA.
    cmd(1,0,1,0,2'b00,2'b00,17'h00400);
    if(dut.bank_open[6]) $fatal(1,"PREA decode failed");

    // REF=001 and ZQ=110 must not be confused with PRE/MRS.
    cmd(1,0,0,1,2'b00,2'b00,17'h00000);
    if(alert_n!==1'b1) $fatal(1,"legal REF decode failed");
    cmd(1,1,1,0,2'b00,2'b00,17'h00400);
    if(alert_n!==1'b1) $fatal(1,"legal ZQCL decode failed");

    // BG1 does not exist on the x16 organization and is rejected.
    cmd(1,1,1,1,2'b10,2'b00,17'h00000);
    if(alert_n!==1'b0) $fatal(1,"illegal x16 BG1 was not flagged");

    $display("PASS MT40A256M16LY-062E:F geometry and command truth table");
    $finish;
  end
  initial begin #2000; $fatal(1,"SDRAM model compliance timeout"); end
endmodule
