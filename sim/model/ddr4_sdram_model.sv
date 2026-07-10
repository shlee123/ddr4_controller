`timescale 1ns/1ps
module ddr4_sdram_model
  import ddr4_ctrl_pkg::*;
#(
  parameter int DQ_W=DDR_DQ_W,
  parameter int ADDR_W=DDR_ADDR_W,
  parameter int BA_W=DDR_BANK_W,
  parameter int BG_W=DDR_BG_W,
  parameter int MEM_AW=20
)(
  input  logic reset_n,
  input  logic ck_t,
  input  logic ck_c,
  input  logic cke,
  input  logic cs_n,
  input  logic act_n,
  input  logic ras_n,
  input  logic cas_n,
  input  logic we_n,
  input  logic [ADDR_W-1:0] a,
  input  logic [BA_W-1:0] ba,
  input  logic [BG_W-1:0] bg,
  input  logic odt,
  inout  wire [DQ_W-1:0] dq,
  inout  wire [DQ_W/8-1:0] dqs_t,
  inout  wire [DQ_W/8-1:0] dqs_c,
  inout  wire [DQ_W/8-1:0] dm_n,
  output logic alert_n
);
  logic [DQ_W-1:0] mem [0:(1<<MEM_AW)-1];
  logic [DDR_ROW_W-1:0] open_row [0:(1<<(BG_W+BA_W))-1];
  logic bank_open [0:(1<<(BG_W+BA_W))-1];
  logic [DQ_W-1:0] dq_drv;
  logic dq_oe;
  assign dq = dq_oe ? dq_drv : 'z;
  assign dqs_t = dq_oe ? {DQ_W/8{ck_t}} : 'z;
  assign dqs_c = dq_oe ? {DQ_W/8{ck_c}} : 'z;
  assign alert_n = 1'b1;

  function automatic int bank_idx(input logic [BG_W-1:0] ibg, input logic [BA_W-1:0] iba);
    bank_idx = {ibg,iba};
  endfunction

  function automatic logic [MEM_AW-1:0] mem_addr(
    input logic [BG_W-1:0] ibg,
    input logic [BA_W-1:0] iba,
    input logic [DDR_ROW_W-1:0] row,
    input logic [DDR_COL_W-1:0] col
  );
    mem_addr = {ibg, iba, row[7:0], col[7:2]};
  endfunction

  typedef struct packed {logic valid; logic [DQ_W-1:0] data;} pipe_t;
  pipe_t rdpipe[0:T_CL_CK];

  always_ff @(posedge ck_t or negedge reset_n) begin
    if(!reset_n) begin
      for(int i=0;i<(1<<(BG_W+BA_W));i++) begin
        bank_open[i] <= 1'b0;
        open_row[i]  <= '0;
      end
      for(int j=0;j<=T_CL_CK;j++) begin
        rdpipe[j].valid <= 1'b0;
        rdpipe[j].data  <= '0;
      end
      dq_oe <= 1'b0;
      dq_drv <= '0;
    end else begin
      dq_oe  <= rdpipe[0].valid;
      dq_drv <= rdpipe[0].data;
      for(int j=0;j<T_CL_CK;j++) rdpipe[j] <= rdpipe[j+1];
      rdpipe[T_CL_CK].valid <= 1'b0;
      rdpipe[T_CL_CK].data  <= '0;

      if(cke && !cs_n) begin
        if(!act_n) begin
          bank_open[bank_idx(bg,ba)] <= 1'b1;
          open_row[bank_idx(bg,ba)]  <= a[DDR_ROW_W-1:0];
        end else begin
          unique case({ras_n,cas_n,we_n})
            3'b101: begin // READ
              if(bank_open[bank_idx(bg,ba)]) begin
                rdpipe[T_CL_CK].valid <= 1'b1;
                rdpipe[T_CL_CK].data  <= mem[mem_addr(bg,ba,open_row[bank_idx(bg,ba)],a[DDR_COL_W-1:0])];
              end
            end
            3'b100: begin // WRITE
              if(bank_open[bank_idx(bg,ba)]) begin
                logic [MEM_AW-1:0] ma;
                ma = mem_addr(bg,ba,open_row[bank_idx(bg,ba)],a[DDR_COL_W-1:0]);
                for(int b=0;b<DQ_W/8;b++) if(!dm_n[b]) mem[ma][8*b +: 8] <= dq[8*b +: 8];
              end
            end
            3'b010: begin // PRECHARGE
              if(a[10]) for(int i=0;i<(1<<(BG_W+BA_W));i++) bank_open[i] <= 1'b0;
              else bank_open[bank_idx(bg,ba)] <= 1'b0;
            end
            3'b001: begin end // REFRESH
            3'b000: begin end // MRS
            default: begin end
          endcase
        end
      end
    end
  end
endmodule
