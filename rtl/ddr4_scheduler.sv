// SPDX-License-Identifier: MIT
// DDR4 initialization/application scheduler.
// V2.2 adds a one-entry next-request prefetch buffer while preserving AR priority.

import ddr4_ctrl_pkg::*;

module ddr4_scheduler #(
  parameter int AXI_ADDR_W = ddr4_ctrl_pkg::AXI_ADDR_W,
  parameter int AXI_DATA_W = ddr4_ctrl_pkg::AXI_DATA_W,
  parameter int DDR_ADDR_W = ddr4_ctrl_pkg::DDR_ADDR_W,
  parameter int DDR_BG_W   = ddr4_ctrl_pkg::DDR_BG_W,
  parameter int DDR_BA_W   = ddr4_ctrl_pkg::DDR_BANK_W,
  parameter int DDR_DQ_W   = ddr4_ctrl_pkg::DDR_DQ_W,
  parameter int DDR_DM_W   = DDR_DQ_W/8
)(
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic                     init_start,
  output logic                     init_done,
  input  logic [16:0]              mr [0:6],

  input  ddr_req_t                 wr_req_data,
  input  logic                     wr_req_empty,
  output logic                     wr_req_rd,

  input  ddr_req_t                 rd_req_data,
  input  logic                     rd_req_empty,
  output logic                     rd_req_rd,

  output ddr_rsp_t                 rsp_data,
  output logic                     rsp_wr,
  input  logic                     rsp_full,

  output logic [AXI_ADDR_W-1:0]    cache_lookup_addr,
  input  logic                     cache_hit,
  input  logic [AXI_DATA_W-1:0]    cache_lookup_data,
  output logic                     cache_write_valid,
  output logic [AXI_ADDR_W-1:0]    cache_write_addr,
  output logic [AXI_DATA_W-1:0]    cache_write_data,

  output logic                     ddr_reset_n,
  output logic                     ddr_cke,
  output logic                     ddr_cs_n,
  output logic                     ddr_act_n,
  output logic                     ddr_ras_n,
  output logic                     ddr_cas_n,
  output logic                     ddr_we_n,
  output logic [DDR_BG_W-1:0]      ddr_bg,
  output logic [DDR_BA_W-1:0]      ddr_ba,
  output logic [DDR_ADDR_W-1:0]    ddr_a,
  output logic                     ddr_odt,
  output logic                     ddr_par,

  input  logic [DDR_DQ_W-1:0]      ddr_dq_in,
  output logic [DDR_DQ_W-1:0]      ddr_dq_out,
  output logic                     ddr_dq_oe,
  output logic [DDR_DM_W-1:0]      ddr_dqs_t_out,
  output logic [DDR_DM_W-1:0]      ddr_dqs_c_out,
  output logic                     ddr_dqs_oe,
  output logic [DDR_DM_W-1:0]      ddr_dm_n_out,
  output logic                     ddr_dm_oe
);

  typedef enum logic [4:0] {
    INIT_RESET,
    INIT_WAIT_CKE,
    INIT_MR3,
    INIT_MR6,
    INIT_MR5,
    INIT_MR4,
    INIT_MR2,
    INIT_MR1,
    INIT_MR0,
    INIT_ZQCL,
    INIT_ZQWAIT,
    INIT_READY,
    APP_IDLE,
    APP_ACT,
    APP_TRCD,
    APP_WR,
    APP_RD,
    APP_RLAT,
    APP_PRE,
    APP_TRP,
    APP_RESP
  } ctrl_state_e;

  ctrl_state_e state;
  logic [15:0] wait_cnt;
  ddr_req_t cur_req;
  ddr_req_t pending_req;
  logic     pending_valid;

  localparam int MR_ADDR_COPY_W = (DDR_ADDR_W < 17) ? DDR_ADDR_W : 17;

  assign cache_lookup_addr = cur_req.addr;

  function automatic [DDR_ADDR_W-1:0] mr_to_addr(input logic [16:0] mr_value);
    begin
      mr_to_addr = '0;
      mr_to_addr[MR_ADDR_COPY_W-1:0] = mr_value[MR_ADDR_COPY_W-1:0];
    end
  endfunction

  function automatic [DDR_BG_W-1:0] addr_bg(input logic [AXI_ADDR_W-1:0] a);
    return a[25 +: DDR_BG_W];
  endfunction

  function automatic [DDR_BA_W-1:0] addr_ba(input logic [AXI_ADDR_W-1:0] a);
    return a[23 +: DDR_BA_W];
  endfunction

  function automatic [DDR_ROW_W-1:0] addr_row(input logic [AXI_ADDR_W-1:0] a);
    return a[22:8];
  endfunction

  function automatic [DDR_COL_W-1:0] addr_col(input logic [AXI_ADDR_W-1:0] a);
    return a[11:2];
  endfunction

  task automatic drive_des;
    begin
      ddr_cs_n  <= 1'b1;
      ddr_act_n <= 1'b1;
      ddr_ras_n <= 1'b1;
      ddr_cas_n <= 1'b1;
      ddr_we_n  <= 1'b1;
    end
  endtask

  logic can_prefetch;
  logic [DDR_ROW_W-1:0] cur_row;
  assign can_prefetch = init_done && !pending_valid && !rsp_full;
  assign cur_row      = addr_row(cur_req.addr);

  always_comb begin
    rd_req_rd = 1'b0;
    wr_req_rd = 1'b0;
    rsp_wr    = 1'b0;

    if (can_prefetch) begin
      if (!rd_req_empty) begin
        rd_req_rd = 1'b1;
      end else if (!wr_req_empty) begin
        wr_req_rd = 1'b1;
      end
    end

    if (state == APP_RESP && !rsp_full) begin
      rsp_wr = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state             <= INIT_RESET;
      wait_cnt          <= '0;
      init_done         <= 1'b0;
      ddr_reset_n       <= 1'b0;
      ddr_cke           <= 1'b0;
      ddr_odt           <= 1'b0;
      ddr_par           <= 1'b0;
      ddr_cs_n          <= 1'b1;
      ddr_act_n         <= 1'b1;
      ddr_ras_n         <= 1'b1;
      ddr_cas_n         <= 1'b1;
      ddr_we_n          <= 1'b1;
      ddr_bg            <= '0;
      ddr_ba            <= '0;
      ddr_a             <= '0;
      ddr_dq_out        <= '0;
      ddr_dq_oe         <= 1'b0;
      ddr_dqs_t_out     <= '0;
      ddr_dqs_c_out     <= '1;
      ddr_dqs_oe        <= 1'b0;
      ddr_dm_n_out      <= '1;
      ddr_dm_oe         <= 1'b0;
      cur_req           <= '0;
      pending_req       <= '0;
      pending_valid     <= 1'b0;
      rsp_data          <= '0;
      cache_write_valid <= 1'b0;
      cache_write_addr  <= '0;
      cache_write_data  <= '0;
    end else begin
      drive_des();
      ddr_reset_n       <= 1'b1;
      ddr_cke           <= 1'b1;
      ddr_odt           <= 1'b1;
      ddr_par           <= 1'b0;
      ddr_dq_oe         <= 1'b0;
      ddr_dqs_oe        <= 1'b0;
      ddr_dm_oe         <= 1'b0;
      cache_write_valid <= 1'b0;
      if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;

      if (rd_req_rd) begin
        pending_req   <= rd_req_data;
        pending_valid <= 1'b1;
      end else if (wr_req_rd) begin
        pending_req   <= wr_req_data;
        pending_valid <= 1'b1;
      end

      unique case (state)
        INIT_RESET: begin
          ddr_reset_n <= 1'b1;
          ddr_cke     <= 1'b0;
          if (init_start) begin
            wait_cnt <= 16'd32;
            state    <= INIT_WAIT_CKE;
          end
        end
        INIT_WAIT_CKE: begin
          ddr_cke <= 1'b1;
          if (wait_cnt == 0) state <= INIT_MR3;
        end
        INIT_MR3: begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= DDR_BA_W'(3); ddr_bg <= '0; ddr_a <= mr_to_addr(mr[3]); wait_cnt <= T_MRD_CK; state <= INIT_MR6;
        end
        INIT_MR6: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= DDR_BA_W'(2); ddr_bg <= DDR_BG_W'(1); ddr_a <= mr_to_addr(mr[6]); wait_cnt <= T_MRD_CK; state <= INIT_MR5;
        end
        INIT_MR5: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= DDR_BA_W'(1); ddr_bg <= DDR_BG_W'(1); ddr_a <= mr_to_addr(mr[5]); wait_cnt <= T_MRD_CK; state <= INIT_MR4;
        end
        INIT_MR4: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= '0; ddr_bg <= DDR_BG_W'(1); ddr_a <= mr_to_addr(mr[4]); wait_cnt <= T_MRD_CK; state <= INIT_MR2;
        end
        INIT_MR2: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= DDR_BA_W'(2); ddr_bg <= '0; ddr_a <= mr_to_addr(mr[2]); wait_cnt <= T_MRD_CK; state <= INIT_MR1;
        end
        INIT_MR1: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= DDR_BA_W'(1); ddr_bg <= '0; ddr_a <= mr_to_addr(mr[1]); wait_cnt <= T_MRD_CK; state <= INIT_MR0;
        end
        INIT_MR0: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b0; ddr_we_n <= 1'b0;
          ddr_ba <= '0; ddr_bg <= '0; ddr_a <= mr_to_addr(mr[0]); wait_cnt <= T_MOD_CK; state <= INIT_ZQCL;
        end
        INIT_ZQCL: if (wait_cnt == 0) begin
          ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b1; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b0;
          ddr_a <= DDR_ADDR_W'(17'h00400); wait_cnt <= T_ZQINIT_CK[15:0]; state <= INIT_ZQWAIT;
        end
        INIT_ZQWAIT: if (wait_cnt == 0) state <= INIT_READY;
        INIT_READY: begin
          init_done <= 1'b1;
          state     <= APP_IDLE;
        end

        APP_IDLE: begin
          if (pending_valid && !rsp_full) begin
            cur_req       <= pending_req;
            pending_valid <= 1'b0;
            state         <= APP_ACT;
          end
        end
        APP_ACT: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b0;
          ddr_ras_n <= cur_row[14];
          ddr_cas_n <= cur_row[13];
          ddr_we_n  <= cur_row[12];
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= DDR_ADDR_W'(addr_row(cur_req.addr));
          wait_cnt  <= T_RCD_CK;
          state     <= APP_TRCD;
        end
        APP_TRCD: if (wait_cnt == 0) begin
          if (cur_req.wr) state <= APP_WR;
          else if (cache_hit) state <= APP_RESP;
          else state <= APP_RD;
        end
        APP_WR: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b1;
          ddr_cas_n <= 1'b0;
          ddr_we_n  <= 1'b0;
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= DDR_ADDR_W'(addr_col(cur_req.addr));
          ddr_dq_out    <= cur_req.wdata[DDR_DQ_W-1:0];
          ddr_dq_oe     <= 1'b1;
          ddr_dqs_t_out <= {DDR_DM_W{clk}};
          ddr_dqs_c_out <= {DDR_DM_W{~clk}};
          ddr_dqs_oe    <= 1'b1;
          ddr_dm_n_out  <= ~cur_req.wstrb[DDR_DM_W-1:0];
          ddr_dm_oe     <= 1'b1;
          cache_write_valid <= 1'b1;
          cache_write_addr  <= cur_req.addr;
          cache_write_data  <= cur_req.wdata;
          wait_cnt <= T_CWL_CK;
          state    <= APP_PRE;
        end
        APP_RD: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b1;
          ddr_cas_n <= 1'b0;
          ddr_we_n  <= 1'b1;
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= DDR_ADDR_W'(addr_col(cur_req.addr));
          wait_cnt  <= T_CL_CK;
          state     <= APP_RLAT;
        end
        APP_RLAT: if (wait_cnt == 0) begin
          cache_write_valid <= 1'b1;
          cache_write_addr  <= cur_req.addr;
          cache_write_data  <= AXI_DATA_W'(ddr_dq_in);
          state <= APP_PRE;
        end
        APP_PRE: begin
          ddr_cs_n  <= 1'b0;
          ddr_act_n <= 1'b1;
          ddr_ras_n <= 1'b0;
          ddr_cas_n <= 1'b1;
          ddr_we_n  <= 1'b0;
          ddr_bg    <= addr_bg(cur_req.addr);
          ddr_ba    <= addr_ba(cur_req.addr);
          ddr_a     <= '0;
          ddr_a[10] <= 1'b1;
          wait_cnt <= T_RP_CK;
          state    <= APP_TRP;
        end
        APP_TRP: if (wait_cnt == 0) state <= APP_RESP;
        APP_RESP: if (!rsp_full) begin
          if (cur_req.wr) begin
            rsp_data <= '{wr:1'b1, addr:cur_req.addr, rdata:'0, resp:2'b00, last:1'b1};
          end else begin
            rsp_data <= '{wr:1'b0, addr:cur_req.addr, rdata:cache_lookup_data, resp:2'b00, last:1'b1};
          end
          state <= APP_IDLE;
        end
        default: state <= INIT_RESET;
      endcase
    end
  end

endmodule : ddr4_scheduler
