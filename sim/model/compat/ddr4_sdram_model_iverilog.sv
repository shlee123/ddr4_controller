// SPDX-License-Identifier: MIT
// Icarus-compatible MT40A256M16LY-062E:F functional model.
`timescale 1ns/1ps
module ddr4_sdram_model #(
  parameter integer DQ_W=16, ADDR_W=17, BA_W=2, BG_W=2,
  parameter integer CL_CK=22, CWL_CK=16, BL_UI=8, MEM_AW=16
)(
  input wire reset_n,ck_t,ck_c,cke,cs_n,act_n,ras_n,cas_n,we_n,
  input wire [ADDR_W-1:0] a, input wire [BA_W-1:0] ba,
  input wire [BG_W-1:0] bg, input wire odt,
  inout wire [DQ_W-1:0] dq,
  inout wire [DQ_W/8-1:0] dqs_t,dqs_c,dm_n,
  output wire alert_n
);
  localparam integer DQS_W=DQ_W/8,NUM_BANKS=8,STORE_DEPTH=1<<MEM_AW;
  reg [14:0] open_row[0:NUM_BANKS-1];
  reg bank_open[0:NUM_BANKS-1];
  reg [15:0] mode_reg[0:6];
  reg [6:0] mr_written;
  reg init_done;
  integer init_step;

  // Decoded MR state is deliberately visible to the compliance testbench.
  integer burst_length,cas_latency,additive_latency,cas_write_latency;
  reg dll_enable,dll_reset,mpr_enable,gear_down,pda_enable,write_crc_enable;
  reg ca_parity_enable,dm_enable,write_dbi_enable,read_dbi_enable;
  reg vrefdq_training_enable,vrefdq_range;
  reg [5:0] vrefdq_value;
  reg [2:0] rtt_nom,rtt_wr,rtt_park;
  reg [1:0] output_drive_strength;

  reg [DQ_W-1:0] store_data[0:STORE_DEPTH-1];
  reg [27:0] store_tag[0:STORE_DEPTH-1];
  reg store_valid[0:STORE_DEPTH-1];
  reg [DQ_W-1:0] dq_out;
  reg [DQS_W-1:0] dqs_t_out,dqs_c_out,dm_out;
  reg dq_oe,dm_oe,alert_reg,read_pending,read_ap;
  integer read_latency,read_ui,read_bank,active_bl;
  reg [27:0] read_base,logical_address;
  reg [MEM_AW-1:0] slot;
  integer i,bank_index,mr_index;

  assign dq=dq_oe?dq_out:{DQ_W{1'bz}};
  assign dqs_t=dq_oe?dqs_t_out:{DQS_W{1'bz}};
  assign dqs_c=dq_oe?dqs_c_out:{DQS_W{1'bz}};
  assign dm_n=dm_oe?dm_out:{DQS_W{1'bz}};
  assign alert_n=alert_reg;

  function integer decode_cl;
    input [4:0] code;
    begin
      case(code)
        0:decode_cl=9; 1:decode_cl=10; 2:decode_cl=11; 3:decode_cl=12;
        4:decode_cl=13; 5:decode_cl=14; 6:decode_cl=15; 7:decode_cl=16;
        8:decode_cl=18; 9:decode_cl=20; 10:decode_cl=22; 11:decode_cl=24;
        12:decode_cl=23; 13:decode_cl=17; 14:decode_cl=19; 15:decode_cl=21;
        16:decode_cl=25; 17:decode_cl=26; 18:decode_cl=27; 19:decode_cl=28;
        20:decode_cl=29; 21:decode_cl=30; 22:decode_cl=31; 23:decode_cl=32;
        default:decode_cl=-1;
      endcase
    end
  endfunction
  function integer decode_cwl;
    input [2:0] code;
    begin
      case(code)
        0:decode_cwl=9;1:decode_cwl=10;2:decode_cwl=11;3:decode_cwl=12;
        4:decode_cwl=14;5:decode_cwl=16;6:decode_cwl=18;default:decode_cwl=-1;
      endcase
    end
  endfunction
  function integer decode_al;
    input [1:0] code; input integer cl;
    begin case(code) 0:decode_al=0;1:decode_al=cl-1;2:decode_al=cl-2;
      default:decode_al=-1; endcase
    end
  endfunction
  function integer command_bl;
    input [1:0] mode; input bc_n;
    begin case(mode) 0:command_bl=8;1:command_bl=bc_n?8:4;
      2:command_bl=4;default:command_bl=-1;endcase
    end
  endfunction

  task decode_mr;
    input integer idx; input [15:0] value;
    integer next_cl;
    begin
      case(idx)
        0: begin
          burst_length=command_bl(value[1:0],1'b1);
          cas_latency=decode_cl({value[12],value[6:4],value[2]});
          dll_reset=value[8];
        end
        1: begin
          dll_enable=~value[0]; output_drive_strength={value[2],value[1]};
          additive_latency=decode_al(value[4:3],cas_latency);
          rtt_nom={value[10],value[9],value[8]};
        end
        2: begin
          cas_write_latency=decode_cwl(value[5:3]);
          rtt_wr={1'b0,value[10:9]}; write_crc_enable=value[12];
        end
        3: begin mpr_enable=value[2]; gear_down=value[3]; pda_enable=value[4]; end
        4: begin end
        5: begin
          ca_parity_enable=(value[2:0]!=0); rtt_park=value[8:6];
          dm_enable=~value[10]; write_dbi_enable=value[11]; read_dbi_enable=value[12];
        end
        6: begin
          vrefdq_value=value[5:0]; vrefdq_range=value[6];
          vrefdq_training_enable=value[7];
        end
      endcase
      next_cl=decode_cl({mode_reg[0][12],mode_reg[0][6:4],mode_reg[0][2]});
      if(idx==1) additive_latency=decode_al(value[4:3],next_cl);
    end
  endtask

  task track_init;
    input integer idx;
    begin
      case(init_step)
        0:if(idx==3)init_step=1;
        1:if(idx==6)init_step=2;
        2:if(idx==5)init_step=3;
        3:if(idx==4)init_step=4;
        4:if(idx==2)init_step=5;
        5:if(idx==1)init_step=6;
        6:if(idx==0)begin init_step=7;init_done=1;end
      endcase
    end
  endtask

  always @(posedge ck_t or negedge reset_n) begin
    if(!reset_n) begin
      for(i=0;i<NUM_BANKS;i=i+1) begin open_row[i]<=0;bank_open[i]<=0;end
      // Datasheet: MR contents are undefined after RESET; X makes misuse visible.
      for(i=0;i<7;i=i+1) mode_reg[i]<={16{1'bx}};
      for(i=0;i<STORE_DEPTH;i=i+1) store_valid[i]<=0;
      mr_written<=0;init_done<=0;init_step<=0;
      burst_length<=BL_UI;cas_latency<=CL_CK;cas_write_latency<=CWL_CK;
      additive_latency<=0;dll_enable<=1;dll_reset<=0;mpr_enable<=0;
      gear_down<=0;pda_enable<=0;write_crc_enable<=0;ca_parity_enable<=0;
      dm_enable<=1;write_dbi_enable<=0;read_dbi_enable<=0;
      vrefdq_training_enable<=0;vrefdq_range<=0;vrefdq_value<=0;
      rtt_nom<=0;rtt_wr<=0;rtt_park<=0;output_drive_strength<=0;
      dq_out<=0;dqs_t_out<=0;dqs_c_out<={DQS_W{1'b1}};dm_out<=0;
      dq_oe<=0;dm_oe<=0;alert_reg<=1;read_pending<=0;read_latency<=0;
      read_ui<=0;read_base<=0;read_bank<=0;read_ap<=0;active_bl<=BL_UI;
    end else begin
      dq_oe<=0;dm_oe<=0;alert_reg<=1;
      if(read_pending) begin
        if(read_latency!=0) read_latency<=read_latency-1;
        else begin
          logical_address=read_base+read_ui;slot=logical_address[MEM_AW-1:0];
          dq_oe<=1;
          dq_out<=mpr_enable?16'h5555:
            ((store_valid[slot]&&store_tag[slot]==logical_address)?
             store_data[slot]:logical_address[15:0]);
          if(read_dbi_enable) begin dm_oe<=1;dm_out<=0;end
          dqs_t_out<={DQS_W{read_ui[0]}};dqs_c_out<={DQS_W{~read_ui[0]}};
          if(read_ui==active_bl-1) begin
            read_pending<=0;read_ui<=0;if(read_ap)bank_open[read_bank]<=0;
          end else read_ui<=read_ui+1;
        end
      end
      if(cke&&!cs_n) begin
        bank_index={bg[0],ba[1:0]};
        if(BG_W>1&&bg[1]!==0)alert_reg<=0;
        if(!act_n)begin bank_open[bank_index]<=1;open_row[bank_index]<=a[14:0];end
        else case({ras_n,cas_n,we_n})
          3'b000:begin
            mr_index={bg[0],ba[1:0]};
            if(mr_index<=6)begin
              mode_reg[mr_index]<=a[15:0];mr_written[mr_index]<=1;
              decode_mr(mr_index,a[15:0]);track_init(mr_index);
            end else alert_reg<=0;
          end
          3'b001:for(i=0;i<NUM_BANKS;i=i+1)if(bank_open[i])alert_reg<=0;
          3'b010:if(a[10])begin for(i=0;i<NUM_BANKS;i=i+1)bank_open[i]<=0;end
                   else bank_open[bank_index]<=0;
          3'b100:if(!bank_open[bank_index])alert_reg<=0;
          3'b101:if(!bank_open[bank_index]&&!mpr_enable)alert_reg<=0;else begin
            read_base<={bg[0],ba[1:0],open_row[bank_index],a[9:0]};
            read_bank<=bank_index;read_ap<=a[10];
            active_bl<=command_bl(mode_reg[0][1:0],a[12]);
            read_latency<=cas_latency+additive_latency-1;
            read_ui<=0;read_pending<=1;
          end
          3'b110:begin end
          3'b111:begin end
        endcase
      end
    end
  end
endmodule
