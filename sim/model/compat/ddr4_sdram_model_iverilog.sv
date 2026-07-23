// SPDX-License-Identifier: MIT
// Icarus-compatible MT40A256M16LY-062E:F functional model.
`timescale 1ns/1ps
module ddr4_sdram_model #(
  parameter integer DQ_W=16, ADDR_W=17, BA_W=2, BG_W=2,
  parameter integer CL_CK=22, BL_UI=8, MEM_AW=16
)(
  input wire reset_n,ck_t,ck_c,cke,cs_n,act_n,ras_n,cas_n,we_n,
  input wire [ADDR_W-1:0] a,
  input wire [BA_W-1:0] ba,
  input wire [BG_W-1:0] bg,
  input wire odt,
  inout wire [DQ_W-1:0] dq,
  inout wire [DQ_W/8-1:0] dqs_t,dqs_c,dm_n,
  output wire alert_n
);
  localparam integer DQS_W=DQ_W/8, NUM_BANKS=8, STORE_DEPTH=1<<MEM_AW;
  reg [14:0] open_row [0:NUM_BANKS-1];
  reg bank_open [0:NUM_BANKS-1];
  reg [15:0] mode_reg [0:6];
  reg [DQ_W-1:0] store_data [0:STORE_DEPTH-1];
  reg [27:0] store_tag [0:STORE_DEPTH-1];
  reg store_valid [0:STORE_DEPTH-1];
  reg [DQ_W-1:0] dq_out;
  reg [DQS_W-1:0] dqs_t_out,dqs_c_out;
  reg dq_oe,alert_reg,read_pending,read_ap;
  integer read_latency,read_ui,read_bank;
  reg [27:0] read_base,logical_address;
  reg [MEM_AW-1:0] slot;
  integer i,bank_index,mr_index;

  assign dq=dq_oe?dq_out:{DQ_W{1'bz}};
  assign dqs_t=dq_oe?dqs_t_out:{DQS_W{1'bz}};
  assign dqs_c=dq_oe?dqs_c_out:{DQS_W{1'bz}};
  assign alert_n=alert_reg;

  always @(posedge ck_t or negedge reset_n) begin
    if(!reset_n) begin
      for(i=0;i<NUM_BANKS;i=i+1) begin open_row[i]<=0; bank_open[i]<=0; end
      for(i=0;i<7;i=i+1) mode_reg[i]<=0;
      for(i=0;i<STORE_DEPTH;i=i+1) store_valid[i]<=0;
      dq_out<=0; dqs_t_out<=0; dqs_c_out<={DQS_W{1'b1}}; dq_oe<=0;
      alert_reg<=1; read_pending<=0; read_latency<=0; read_ui<=0;
      read_base<=0; read_bank<=0; read_ap<=0;
    end else begin
      dq_oe<=0; alert_reg<=1;
      if(read_pending) begin
        if(read_latency!=0) read_latency<=read_latency-1;
        else begin
          logical_address=read_base+read_ui;
          slot=logical_address[MEM_AW-1:0];
          dq_oe<=1;
          dq_out<=(store_valid[slot]&&store_tag[slot]==logical_address)?
                   store_data[slot]:logical_address[15:0];
          dqs_t_out<={DQS_W{read_ui[0]}};
          dqs_c_out<={DQS_W{~read_ui[0]}};
          if(read_ui==BL_UI-1) begin
            read_pending<=0; read_ui<=0;
            if(read_ap) bank_open[read_bank]<=0;
          end else read_ui<=read_ui+1;
        end
      end
      if(cke&&!cs_n) begin
        bank_index={bg[0],ba[1:0]};
        if(BG_W>1&&bg[1]!==1'b0) alert_reg<=0;
        if(!act_n) begin bank_open[bank_index]<=1; open_row[bank_index]<=a[14:0]; end
        else case({ras_n,cas_n,we_n})
          3'b000: begin
            mr_index={bg[0],ba[1:0]};
            if(mr_index<=6) mode_reg[mr_index]<=a[15:0]; else alert_reg<=0;
          end
          3'b001: for(i=0;i<NUM_BANKS;i=i+1) if(bank_open[i]) alert_reg<=0;
          3'b010: if(a[10]) begin
            for(i=0;i<NUM_BANKS;i=i+1) bank_open[i]<=0;
          end else bank_open[bank_index]<=0;
          3'b100: if(!bank_open[bank_index]) alert_reg<=0;
          3'b101: if(!bank_open[bank_index]) alert_reg<=0; else begin
            read_base<={bg[0],ba[1:0],open_row[bank_index],a[9:0]};
            read_bank<=bank_index; read_ap<=a[10];
            read_latency<=CL_CK-1; read_ui<=0; read_pending<=1;
          end
          3'b110: begin end
          3'b111: begin end
          default: begin end
        endcase
      end
    end
  end
endmodule
