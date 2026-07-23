// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_ddr4_sdram_model_compliance;
  reg ck_t=0,reset_n=0,cke=0,cs_n=1,act_n=1,ras_n=1,cas_n=1,we_n=1,odt=0;
  reg [16:0] a=0;reg [1:0] ba=0,bg=0;
  wire [15:0] dq;wire [1:0] dqs_t,dqs_c,dm_n;wire alert_n;
  always #1 ck_t=~ck_t;
  ddr4_sdram_model #(.CL_CK(22)) dut(
    .reset_n,.ck_t,.ck_c(~ck_t),.cke,.cs_n,.act_n,.ras_n,.cas_n,.we_n,
    .a,.ba,.bg,.odt,.dq,.dqs_t,.dqs_c,.dm_n,.alert_n);
  task cmd;
    input ia,ir,ic,iw;input[1:0]ibg,iba;input[16:0]iaa;
    begin @(negedge ck_t);cs_n=0;act_n=ia;ras_n=ir;cas_n=ic;we_n=iw;
      bg=ibg;ba=iba;a=iaa;@(negedge ck_t);cs_n=1;act_n=1;ras_n=1;
      cas_n=1;we_n=1;bg=0;ba=0;a=0;end
  endtask
  task mrs;input[2:0]idx;input[15:0]value;
    begin cmd(1,0,0,0,{1'b0,idx[2]},idx[1:0],{1'b0,value});end
  endtask
  initial begin
    repeat(3)@(posedge ck_t);reset_n=1;cke=1;
    if(dut.mode_reg[0]!==16'hxxxx||dut.init_done!==0)
      $fatal(1,"MR reset state must be undefined/not initialized");
    // Required power-up order. Values choose BL8, CL22, CWL16 and exercise features.
    mrs(3,16'h0008); // gear-down
    mrs(6,16'h00c9); // training, range 1, value 9
    mrs(5,16'h1c80); // RTT_PARK, DM disabled, read/write DBI
    mrs(4,16'h1800); // read/write preamble selections
    mrs(2,16'h1028); // CWL16, write CRC
    mrs(1,16'h0100); // DLL enabled, RTT_NOM
    mrs(0,16'h0050); // BL8, CL22
    if(!dut.init_done||dut.mr_written!==7'h7f)$fatal(1,"MRS init tracking failed");
    if(dut.cas_latency!=22||dut.cas_write_latency!=16||dut.burst_length!=8)
      $fatal(1,"MR0/MR2 latency or burst decode failed");
    if(!dut.dll_enable||!dut.gear_down||!dut.write_crc_enable)
      $fatal(1,"MR1/MR2/MR3 feature decode failed");
    if(dut.dm_enable||!dut.write_dbi_enable||!dut.read_dbi_enable)
      $fatal(1,"MR5 DM/DBI decode failed");
    if(!dut.vrefdq_training_enable||!dut.vrefdq_range||dut.vrefdq_value!=9)
      $fatal(1,"MR6 VREFDQ decode failed");
    if(!dut.read_preamble_2t||!dut.write_preamble_2t)
      $fatal(1,"MR4 preamble decode failed");
    // Runtime MRS write must immediately synchronize functional state.
    mrs(0,16'h0040); // CL18
    if(dut.cas_latency!=18||dut.mode_reg[0]!=16'h0040)
      $fatal(1,"runtime MR0 write did not synchronize CL");
    mrs(2,16'h0020); // CWL14
    if(dut.cas_write_latency!=14)$fatal(1,"runtime MR2 write did not synchronize CWL");
    // x16 bank geometry remains covered.
    cmd(0,1,1,1,2'b01,2'b10,17'h01234);
    if(!dut.bank_open[6]||dut.open_row[6]!==15'h1234)$fatal(1,"x16 bank map");
    cmd(1,1,0,1,2'b01,2'b10,17'h002a5);
    if(dut.read_base!=={1'b1,2'b10,15'h1234,10'h2a5})$fatal(1,"address map");
    $display("PASS MT40A256M16LY-062E:F MR0-MR6 decode and synchronization");
    $finish;
  end
  initial begin #4000;$fatal(1,"SDRAM model compliance timeout");end
endmodule
