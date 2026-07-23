`timescale 1ns/1ps
module tb_ddr4_controller_m34;
  localparam integer T_MOD_CK=24;
  reg clk=0,rst_n=0,controller_init_done=0;
  reg [1:0] lane_sample_ok;
  wire phy_init_done,phy_init_fail,training_busy,train_mrs_valid;
  wire [2:0] training_phase,train_mrs_index;
  wire [16:0] train_mrs_value;
  wire [9:0] write_level_tap,read_level_tap;
  reg [15:0] ctl_dq_out=16'h5aa5;
  reg ctl_dq_oe=0,ctl_dqs_oe=0,ctl_dm_oe=0;
  reg [1:0] ctl_dqs_t_out=2'b10,ctl_dqs_c_out=2'b01,ctl_dm_n_out=2'b00;
  wire [15:0] ctl_dq_in;
  wire [15:0] ddr_dq;
  wire [1:0] ddr_dqs_t,ddr_dqs_c,ddr_dm_n;
  integer cycles,mrs_count,last_mrs_cycle;
  reg [2:0] seen_index [0:3];
  reg [16:0] seen_value [0:3];

  always #1 clk=~clk;
  always @* begin
    lane_sample_ok[0]=(dut.tap>=5)&&(dut.tap<=11);
    lane_sample_ok[1]=(dut.tap>=13)&&(dut.tap<=23);
  end
  always @(posedge clk) begin
    if (rst_n) cycles=cycles+1;
    if (train_mrs_valid) begin
      if ((mrs_count>0)&&((cycles-last_mrs_cycle)<T_MOD_CK))
        $fatal(1,"M34 MRS commands violate tMOD");
      seen_index[mrs_count]=train_mrs_index;
      seen_value[mrs_count]=train_mrs_value;
      last_mrs_cycle=cycles;
      mrs_count=mrs_count+1;
    end
  end

  ddr4_phy_wrapper #(.T_MOD_CK(T_MOD_CK)) dut(
    .clk,.rst_n,.controller_init_done,.mr1_normal(17'h00000),.mr3_normal(17'h00000),
    .lane_sample_ok,.phy_init_done,.phy_init_fail,.training_busy,.training_phase,
    .write_level_tap,.read_level_tap,.train_mrs_valid,.train_mrs_index,.train_mrs_value,
    .ctl_dq_out,.ctl_dq_oe,.ctl_dqs_t_out,.ctl_dqs_c_out,.ctl_dqs_oe,
    .ctl_dm_n_out,.ctl_dm_oe,.ctl_dq_in,.ddr_dq,.ddr_dqs_t,.ddr_dqs_c,.ddr_dm_n);

  initial begin
    cycles=0;mrs_count=0;last_mrs_cycle=-1000;
    repeat(3) @(posedge clk); rst_n=1;
    repeat(2) @(posedge clk); controller_init_done=1;
    while(!phy_init_done&&!phy_init_fail&&cycles<300) @(posedge clk);
    if(!phy_init_done||phy_init_fail)$fatal(1,"M34 training did not complete");
    if(mrs_count!=4)$fatal(1,"M34 expected four training MRS commands, got %0d",mrs_count);
    if(seen_index[0]!=1||seen_value[0]!=17'h00080)$fatal(1,"MR1 write leveling enable incorrect");
    if(seen_index[1]!=1||seen_value[1]!=17'h00000)$fatal(1,"MR1 write leveling restore incorrect");
    if(seen_index[2]!=3||seen_value[2]!=17'h00004)$fatal(1,"MR3 MPR enable incorrect");
    if(seen_index[3]!=3||seen_value[3]!=17'h00000)$fatal(1,"MR3 MPR restore incorrect");
    if((cycles-last_mrs_cycle)<T_MOD_CK)$fatal(1,"phy_init_done asserted before final tMOD");
    if(write_level_tap[4:0]!=8||write_level_tap[9:5]!=18)
      $fatal(1,"M34 write centers wrong: %0d %0d",write_level_tap[4:0],write_level_tap[9:5]);
    if(read_level_tap[4:0]!=8||read_level_tap[9:5]!=18)
      $fatal(1,"M34 read centers wrong: %0d %0d",read_level_tap[4:0],read_level_tap[9:5]);
    if(ddr_dq!==16'hzzzz)$fatal(1,"M34 pins driven before controller request");
    ctl_dq_oe=1;ctl_dqs_oe=1;ctl_dm_oe=1;#1;
    if(ddr_dq!==16'h5aa5||ddr_dqs_t!==2'b10||ddr_dm_n!==2'b00)
      $fatal(1,"M34 controller/PHY pin forwarding failed");
    $display("PASS M34 PHY MRS sequence, x16 lane training and pin isolation");
    $finish;
  end
endmodule
