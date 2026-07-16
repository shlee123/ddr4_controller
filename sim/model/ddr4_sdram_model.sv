`timescale 1ns/1ps

module ddr4_sdram_model
  import ddr4_ctrl_pkg::*;
#(
  parameter int DQ_W   = DDR_DQ_W,
  parameter int ADDR_W = DDR_ADDR_W,
  parameter int BA_W   = DDR_BANK_W,
  parameter int BG_W   = DDR_BG_W,
  parameter int MEM_AW = 20,
  parameter int BL_UI  = DDR_BL8_UI,
  parameter int CL_CK  = T_CL_CK,
  parameter int CWL_CK = T_CWL_CK
)(
  input  logic                   reset_n,
  input  logic                   ck_t,
  input  logic                   ck_c,
  input  logic                   cke,
  input  logic                   cs_n,
  input  logic                   act_n,
  input  logic                   ras_n,
  input  logic                   cas_n,
  input  logic                   we_n,
  input  logic [ADDR_W-1:0]      a,
  input  logic [BA_W-1:0]        ba,
  input  logic [BG_W-1:0]        bg,
  input  logic                   odt,
  inout  wire  [DQ_W-1:0]        dq,
  inout  wire  [DQ_W/8-1:0]      dqs_t,
  inout  wire  [DQ_W/8-1:0]      dqs_c,
  inout  wire  [DQ_W/8-1:0]      dm_n,
  output logic                   alert_n
);

  localparam int NUM_BANKS = 1 << (BG_W + BA_W);
  localparam int DM_W      = DQ_W / 8;

  logic [DQ_W-1:0] mem [0:(1<<MEM_AW)-1];
  logic [DDR_ROW_W-1:0] open_row [0:NUM_BANKS-1];
  logic bank_open [0:NUM_BANKS-1];

  logic [DQ_W-1:0] dq_drv;
  logic [DM_W-1:0] dqs_t_drv;
  logic [DM_W-1:0] dqs_c_drv;
  logic dq_oe;

  logic rd_pending;
  logic wr_pending;
  logic [7:0] rd_latency;
  logic [7:0] wr_latency;
  logic [3:0] rd_ui;
  logic [3:0] wr_ui;
  logic [MEM_AW-1:0] rd_base;
  logic [MEM_AW-1:0] wr_base;

  assign dq      = dq_oe ? dq_drv : 'z;
  assign dqs_t   = dq_oe ? dqs_t_drv : 'z;
  assign dqs_c   = dq_oe ? dqs_c_drv : 'z;
  assign alert_n = 1'b1;

  function automatic int bank_idx(
    input logic [BG_W-1:0] ibg,
    input logic [BA_W-1:0] iba
  );
    bank_idx = {ibg, iba};
  endfunction

  function automatic logic [MEM_AW-1:0] mem_addr(
    input logic [BG_W-1:0] ibg,
    input logic [BA_W-1:0] iba,
    input logic [DDR_ROW_W-1:0] row,
    input logic [DDR_COL_W-1:0] col
  );
    logic [BG_W+BA_W+8+8-1:0] packed_addr;
    begin
      packed_addr = {ibg, iba, row[7:0], col[7:0]};
      mem_addr = packed_addr[MEM_AW-1:0];
    end
  endfunction

  integer i;
  initial begin
    // Initialize a small deterministic window for smoke/regression tests.
    // The rest of the behavioral array remains uninitialized until written.
    for (i = 0; i < 256; i = i + 1) begin
      mem[i] = DQ_W'(i);
    end
  end

  always_ff @(posedge ck_t or negedge reset_n) begin
    integer b;
    integer bank;
    logic [MEM_AW-1:0] ma;

    if (!reset_n) begin
      for (i = 0; i < NUM_BANKS; i = i + 1) begin
        bank_open[i] <= 1'b0;
        open_row[i]  <= '0;
      end
      dq_drv    <= '0;
      dqs_t_drv <= '0;
      dqs_c_drv <= '1;
      dq_oe     <= 1'b0;
      rd_pending <= 1'b0;
      wr_pending <= 1'b0;
      rd_latency <= '0;
      wr_latency <= '0;
      rd_ui      <= '0;
      wr_ui      <= '0;
      rd_base    <= '0;
      wr_base    <= '0;
    end else begin
      dq_oe <= 1'b0;

      // READ burst output.  Data is driven for BL8 unit intervals after CL.
      if (rd_pending) begin
        if (rd_latency != 0) begin
          rd_latency <= rd_latency - 1'b1;
        end else begin
          dq_oe     <= 1'b1;
          dq_drv    <= mem[rd_base + rd_ui];
          dqs_t_drv <= {DM_W{rd_ui[0]}};
          dqs_c_drv <= {DM_W{~rd_ui[0]}};
          if (rd_ui == BL_UI-1) begin
            rd_pending <= 1'b0;
            rd_ui      <= '0;
          end else begin
            rd_ui <= rd_ui + 1'b1;
          end
        end
      end

      // WRITE burst input.  The controller drives DQ/DM during the BL8 window.
      if (wr_pending) begin
        if (wr_latency != 0) begin
          wr_latency <= wr_latency - 1'b1;
        end else begin
          for (b = 0; b < DM_W; b = b + 1) begin
            if (dm_n[b] === 1'b0) begin
              mem[wr_base + wr_ui][8*b +: 8] <= dq[8*b +: 8];
            end
          end
          if (wr_ui == BL_UI-1) begin
            wr_pending <= 1'b0;
            wr_ui      <= '0;
          end else begin
            wr_ui <= wr_ui + 1'b1;
          end
        end
      end

      if (cke && !cs_n) begin
        bank = bank_idx(bg, ba);

        if (!act_n) begin
          bank_open[bank] <= 1'b1;
          open_row[bank]  <= a[DDR_ROW_W-1:0];
        end else begin
          unique case ({ras_n, cas_n, we_n})
            3'b101: begin // READ / RDA
              if (bank_open[bank]) begin
                ma = mem_addr(bg, ba, open_row[bank], a[DDR_COL_W-1:0]);
                rd_base    <= ma;
                rd_latency <= (CL_CK > 0) ? CL_CK-1 : 0;
                rd_ui      <= '0;
                rd_pending <= 1'b1;
              end
            end

            3'b100: begin // WRITE / WRA
              if (bank_open[bank]) begin
                ma = mem_addr(bg, ba, open_row[bank], a[DDR_COL_W-1:0]);
                wr_base    <= ma;
                wr_latency <= (CWL_CK > 0) ? CWL_CK-1 : 0;
                wr_ui      <= '0;
                wr_pending <= 1'b1;
              end
            end

            3'b110: begin // PRECHARGE/PRECHARGE ALL
              if (a[10]) begin
                for (i = 0; i < NUM_BANKS; i = i + 1) begin
                  bank_open[i] <= 1'b0;
                end
              end else begin
                bank_open[bank] <= 1'b0;
              end
            end

            3'b010: begin end // REFRESH
            3'b011: begin end // MRS
            3'b001: begin end // ZQCL/ZQCS
            default: begin end
          endcase
        end
      end
    end
  end

endmodule : ddr4_sdram_model
