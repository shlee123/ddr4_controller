// SPDX-License-Identifier: MIT
// Micron MT40A256M16LY-062E:F protocol-functional simulation model.
// Organization: 256M x 16, BG0, BA[1:0], A[14:0], A[9:0], BL8.
`timescale 1ns/1ps

module ddr4_sdram_model
  import ddr4_ctrl_pkg::*;
#(
  parameter int DQ_W = 16,
  parameter int ADDR_W = DDR_ADDR_W,
  parameter int BA_W = 2,
  parameter int BG_W = DDR_BG_W,
  parameter int BL_UI = 8,
  parameter int CL_CK = 22,
  parameter int CWL_CK = 16,
  parameter int MEM_AW = 20,
  parameter bit STRICT_TIMING = 1'b0,
  parameter int TRCD_CK = 7,
  parameter int TRP_CK = 7,
  parameter int TRAS_CK = 16,
  parameter int TRFC_CK = 130,
  parameter int TMRD_CK = 8
)(
  input logic reset_n, ck_t, ck_c, cke, cs_n, act_n,
  input logic ras_n, cas_n, we_n,
  input logic [ADDR_W-1:0] a,
  input logic [BA_W-1:0] ba,
  input logic [BG_W-1:0] bg,
  input logic odt,
  inout wire [DQ_W-1:0] dq,
  inout wire [DQ_W/8-1:0] dqs_t, dqs_c, dm_n,
  output logic alert_n
);
  localparam int DQS_W = DQ_W/8;
  localparam int NUM_BANKS = 8;
  typedef logic [27:0] mem_key_t;
  localparam int STORE_DEPTH = 1 << MEM_AW;
  logic [DQ_W-1:0] store_data [0:STORE_DEPTH-1];
  mem_key_t store_tag [0:STORE_DEPTH-1];
  logic store_valid [0:STORE_DEPTH-1];
  logic [14:0] open_row [0:NUM_BANKS-1];
  logic bank_open [0:NUM_BANKS-1];
  logic [15:0] mr [0:6];
  logic [6:0] mr_written;
  logic init_done;
  integer init_step;
  integer burst_length, cas_latency, additive_latency, cas_write_latency;
  logic dll_enable, dll_reset, mpr_enable, gear_down, pda_enable;
  logic write_crc_enable, ca_parity_enable, dm_enable;
  logic write_dbi_enable, read_dbi_enable;
  logic vrefdq_training_enable, vrefdq_range;
  logic [5:0] vrefdq_value;
  logic [2:0] rtt_nom, rtt_wr, rtt_park;
  logic [1:0] output_drive_strength;
  integer act_age [0:NUM_BANKS-1];
  integer pre_age [0:NUM_BANKS-1];
  integer refresh_age, mrs_age;

  logic [DQ_W-1:0] dq_drv;
  logic [DQS_W-1:0] dqs_t_drv, dqs_c_drv;
  logic dq_oe, rd_pending, wr_pending, rd_ap, wr_ap;
  integer rd_half_latency, wr_half_latency, rd_ui, wr_ui;
  integer rd_bl, wr_bl;
  integer rd_bank, wr_bank;
  mem_key_t rd_base, wr_base;

  assign dq = dq_oe ? dq_drv : 'z;
  assign dqs_t = dq_oe ? dqs_t_drv : 'z;
  assign dqs_c = dq_oe ? dqs_c_drv : 'z;

  function automatic integer bank_idx(input logic ibg0, input logic [1:0] iba);
    bank_idx = {ibg0, iba};
  endfunction
  function automatic mem_key_t logical_addr(
    input logic ibg0, input logic [1:0] iba,
    input logic [14:0] row, input logic [9:0] col);
    logical_addr = {ibg0, iba, row, col};
  endfunction
  task automatic violation(input string msg);
    begin
      alert_n <= 1'b0;
      if (STRICT_TIMING) $error("MT40A256M16LY-062E:F violation: %s", msg);
    end
  endtask

  function automatic integer decode_cl(input logic [4:0] code);
    case (code)
      0:decode_cl=9; 1:decode_cl=10; 2:decode_cl=11; 3:decode_cl=12;
      4:decode_cl=13; 5:decode_cl=14; 6:decode_cl=15; 7:decode_cl=16;
      8:decode_cl=18; 9:decode_cl=20; 10:decode_cl=22; 11:decode_cl=24;
      12:decode_cl=23; 13:decode_cl=17; 14:decode_cl=19; 15:decode_cl=21;
      16:decode_cl=25; 17:decode_cl=26; 18:decode_cl=27; 19:decode_cl=28;
      20:decode_cl=29; 21:decode_cl=30; 22:decode_cl=31; 23:decode_cl=32;
      default:decode_cl=-1;
    endcase
  endfunction
  function automatic integer decode_cwl(input logic [2:0] code);
    case (code)
      0:decode_cwl=9; 1:decode_cwl=10; 2:decode_cwl=11; 3:decode_cwl=12;
      4:decode_cwl=14; 5:decode_cwl=16; 6:decode_cwl=18; default:decode_cwl=-1;
    endcase
  endfunction
  function automatic integer decode_al(input logic [1:0] code, input integer cl);
    case (code) 0:decode_al=0; 1:decode_al=cl-1; 2:decode_al=cl-2;
      default:decode_al=-1; endcase
  endfunction
  function automatic integer command_bl(input logic [1:0] mode,input logic bc_n);
    case (mode) 0:command_bl=8; 1:command_bl=bc_n?8:4;
      2:command_bl=4; default:command_bl=-1; endcase
  endfunction
  task automatic decode_mr(input integer idx,input logic [15:0] value);
    begin
      case(idx)
        0: begin burst_length=command_bl(value[1:0],1'b1);
          cas_latency=decode_cl({value[12],value[6:4],value[2]});
          dll_reset=value[8]; end
        1: begin dll_enable=~value[0];output_drive_strength={value[2],value[1]};
          additive_latency=decode_al(value[4:3],cas_latency);
          rtt_nom={value[10],value[9],value[8]};end
        2: begin cas_write_latency=decode_cwl(value[5:3]);
          rtt_wr={1'b0,value[10:9]};write_crc_enable=value[12];end
        3: begin mpr_enable=value[2];gear_down=value[3];pda_enable=value[4];end
        4: begin end
        5: begin ca_parity_enable=(value[2:0]!=0);rtt_park=value[8:6];
          dm_enable=~value[10];write_dbi_enable=value[11];read_dbi_enable=value[12];end
        6: begin vrefdq_value=value[5:0];vrefdq_range=value[6];
          vrefdq_training_enable=value[7];end
      endcase
    end
  endtask
  task automatic track_init(input integer idx);
    begin
      case(init_step)
        0:if(idx==3)init_step=1; 1:if(idx==6)init_step=2;
        2:if(idx==5)init_step=3; 3:if(idx==4)init_step=4;
        4:if(idx==2)init_step=5; 5:if(idx==1)init_step=6;
        6:if(idx==0)begin init_step=7;init_done=1;end
      endcase
    end
  endtask

  integer i, bank, mr_index;
  mem_key_t key;
  logic [MEM_AW-1:0] slot;

  always @(posedge ck_t or negedge reset_n) begin
    if (!reset_n) begin
      alert_n <= 1'b1;
      refresh_age <= TRFC_CK;
      mrs_age <= TMRD_CK;
      rd_pending <= 1'b0;
      wr_pending <= 1'b0;
      rd_half_latency <= 0;
      wr_half_latency <= 0;
      rd_ui <= 0;
      wr_ui <= 0;
      rd_bl <= BL_UI;
      wr_bl <= BL_UI;
      mr_written <= '0;
      init_done <= 1'b0;
      init_step <= 0;
      burst_length <= BL_UI;
      cas_latency <= CL_CK;
      cas_write_latency <= CWL_CK;
      additive_latency <= 0;
      dll_enable <= 1'b1; dll_reset <= 1'b0; mpr_enable <= 1'b0;
      gear_down <= 1'b0; pda_enable <= 1'b0; write_crc_enable <= 1'b0;
      ca_parity_enable <= 1'b0; dm_enable <= 1'b1;
      write_dbi_enable <= 1'b0; read_dbi_enable <= 1'b0;
      vrefdq_training_enable <= 1'b0; vrefdq_range <= 1'b0;
      vrefdq_value <= '0; rtt_nom <= '0; rtt_wr <= '0; rtt_park <= '0;
      output_drive_strength <= '0;
      for (i=0; i<NUM_BANKS; i=i+1) begin
        bank_open[i] <= 1'b0;
        open_row[i] <= '0;
        act_age[i] <= TRAS_CK;
        pre_age[i] <= TRP_CK;
      end
      // Datasheet defines MR0-MR6 as undefined after RESET.
      for (i=0; i<7; i=i+1) mr[i] <= 'x;
      for (i=0; i<STORE_DEPTH; i=i+1) store_valid[i] <= 1'b0;
    end else begin
      if (!alert_n) alert_n <= 1'b1;
      if (refresh_age < TRFC_CK) refresh_age <= refresh_age + 1;
      if (mrs_age < TMRD_CK) mrs_age <= mrs_age + 1;
      for (i=0; i<NUM_BANKS; i=i+1) begin
        if (act_age[i] < TRAS_CK) act_age[i] <= act_age[i] + 1;
        if (pre_age[i] < TRP_CK) pre_age[i] <= pre_age[i] + 1;
      end

      if (cke && !cs_n) begin
        bank = bank_idx(bg[0], ba[1:0]);
        if (BG_W > 1 && bg[1] !== 1'b0)
          violation("BG1 must be LOW/not populated for x16");
        if (!act_n) begin
          if (refresh_age < TRFC_CK) violation("ACT before tRFC");
          if (pre_age[bank] < TRP_CK) violation("ACT before tRP");
          if (bank_open[bank]) violation("ACT to open bank");
          bank_open[bank] <= 1'b1;
          open_row[bank] <= a[14:0];
          act_age[bank] <= 0;
        end else case ({ras_n,cas_n,we_n})
          3'b000: begin // MRS
            mr_index = {bg[0],ba[1:0]};
            if (mrs_age < TMRD_CK) violation("MRS before tMRD");
            if (mr_index <= 6) begin
              mr[mr_index] <= a[15:0];
              mr_written[mr_index] <= 1'b1;
              decode_mr(mr_index,a[15:0]);
              track_init(mr_index);
            end
            else violation("reserved MR7");
            mrs_age <= 0;
          end
          3'b001: begin // REF
            for (i=0; i<NUM_BANKS; i=i+1)
              if (bank_open[i]) violation("REF requires precharged banks");
            if (refresh_age < TRFC_CK) violation("REF before tRFC");
            refresh_age <= 0;
          end
          3'b010: begin // PRE/PREA
            if (a[10]) begin
              for (i=0; i<NUM_BANKS; i=i+1) begin
                if (bank_open[i] && act_age[i] < TRAS_CK) violation("PREA before tRAS");
                bank_open[i] <= 1'b0;
                pre_age[i] <= 0;
              end
            end else begin
              if (bank_open[bank] && act_age[bank] < TRAS_CK) violation("PRE before tRAS");
              bank_open[bank] <= 1'b0;
              pre_age[bank] <= 0;
            end
          end
          3'b100: begin // WR/WRA
            if (!bank_open[bank]) violation("WRITE to closed bank");
            if (act_age[bank] < TRCD_CK) violation("WRITE before tRCD");
            wr_base <= logical_addr(bg[0],ba[1:0],open_row[bank],a[9:0]);
            wr_bank <= bank;
            wr_ap <= a[10];
            wr_ui <= 0;
            wr_half_latency <= 2*(cas_write_latency+additive_latency);
            wr_bl <= command_bl(mr[0][1:0],a[12]);
            wr_pending <= 1'b1;
          end
          3'b101: begin // RD/RDA
            if (!bank_open[bank]) violation("READ to closed bank");
            if (act_age[bank] < TRCD_CK) violation("READ before tRCD");
            rd_base <= logical_addr(bg[0],ba[1:0],open_row[bank],a[9:0]);
            rd_bank <= bank;
            rd_ap <= a[10];
            rd_ui <= 0;
            rd_half_latency <= 2*(cas_latency+additive_latency);
            rd_bl <= command_bl(mr[0][1:0],a[12]);
            rd_pending <= 1'b1;
          end
          3'b110: begin // ZQCL/ZQCS
            for (i=0; i<NUM_BANKS; i=i+1)
              if (bank_open[i]) violation("ZQ requires precharged banks");
          end
          3'b111: begin end // NOP
          default: begin end
        endcase
      end
    end
  end

  // BL8 read transfer on both CK edges (four CK periods).
  always @(ck_t or negedge reset_n) begin
    if (!reset_n) begin
      dq_drv <= '0;
      dqs_t_drv <= '0;
      dqs_c_drv <= '1;
      dq_oe <= 1'b0;
    end else begin
      dq_oe <= 1'b0;
      if (rd_pending) begin
        if (rd_half_latency > 0) rd_half_latency <= rd_half_latency - 1;
        else begin
          key = rd_base + rd_ui;
          slot = key[MEM_AW-1:0];
          dq_drv <= mpr_enable ? {DQ_W/8{8'h55}} :
                    ((store_valid[slot] && store_tag[slot] == key)
                    ? store_data[slot] : 'x);
          dqs_t_drv <= {DQS_W{~ck_t}};
          dqs_c_drv <= {DQS_W{ck_t}};
          dq_oe <= 1'b1;
          if (rd_ui == rd_bl-1) begin
            rd_pending <= 1'b0;
            rd_ui <= 0;
            if (rd_ap) begin
              bank_open[rd_bank] <= 1'b0;
              pre_age[rd_bank] <= 0;
            end
          end else rd_ui <= rd_ui + 1;
        end
      end
      if (wr_pending && wr_half_latency > 0)
        wr_half_latency <= wr_half_latency - 1;
    end
  end

  // Write data is captured on both edges of incoming DQS, with per-byte DM.
  always @(dqs_t[0] or negedge reset_n) begin
    integer lane;
    if (!reset_n) wr_ui <= 0;
    else if (wr_pending && wr_half_latency == 0 &&
             (dqs_t[0] === 1'b0 || dqs_t[0] === 1'b1)) begin
      key = wr_base + wr_ui;
      slot = key[MEM_AW-1:0];
      if (!store_valid[slot] || store_tag[slot] != key)
        store_data[slot] = 'x;
      store_tag[slot] = key;
      store_valid[slot] = 1'b1;
      for (lane=0; lane<DQS_W; lane=lane+1) begin
        if (!dm_enable || dm_n[lane] === 1'b0)
          store_data[slot][8*lane +: 8] =
            write_dbi_enable && dm_n[lane] === 1'b1
              ? ~dq[8*lane +: 8] : dq[8*lane +: 8];
      end
      if (wr_ui == wr_bl-1) begin
        wr_pending <= 1'b0;
        wr_ui <= 0;
        if (wr_ap) begin
          bank_open[wr_bank] <= 1'b0;
          pre_age[wr_bank] <= 0;
        end
      end else wr_ui <= wr_ui + 1;
    end
  end
endmodule
