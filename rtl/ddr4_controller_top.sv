// SPDX-License-Identifier: MIT
// DDR4 controller top-level, Version 2.
// Synthesis-oriented RTL skeleton with AXI burst-read support and DDR4 BL8 DQ/DQS PHY shim.

import ddr4_ctrl_pkg::*;

module ddr4_controller_top #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 32,
  parameter int APB_ADDR_W = 32,
  parameter int APB_DATA_W = 32,
  parameter int DDR_ADDR_W = 17,
  parameter int DDR_BG_W   = 2,
  parameter int DDR_BA_W   = 2,
  parameter int DDR_DQ_W   = 16,
  parameter int DDR_DM_W   = DDR_DQ_W/8
)(
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic [AXI_ADDR_W-1:0]    s_axi_awaddr,
  input  logic [7:0]               s_axi_awlen,
  input  logic [2:0]               s_axi_awsize,
  input  logic [1:0]               s_axi_awburst,
  input  logic                     s_axi_awvalid,
  output logic                     s_axi_awready,

  input  logic [AXI_DATA_W-1:0]    s_axi_wdata,
  input  logic [AXI_DATA_W/8-1:0]  s_axi_wstrb,
  input  logic                     s_axi_wlast,
  input  logic                     s_axi_wvalid,
  output logic                     s_axi_wready,

  output logic [1:0]               s_axi_bresp,
  output logic                     s_axi_bvalid,
  input  logic                     s_axi_bready,

  input  logic [AXI_ADDR_W-1:0]    s_axi_araddr,
  input  logic [7:0]               s_axi_arlen,
  input  logic [2:0]               s_axi_arsize,
  input  logic [1:0]               s_axi_arburst,
  input  logic                     s_axi_arvalid,
  output logic                     s_axi_arready,

  output logic [AXI_DATA_W-1:0]    s_axi_rdata,
  output logic [1:0]               s_axi_rresp,
  output logic                     s_axi_rlast,
  output logic                     s_axi_rvalid,
  input  logic                     s_axi_rready,

  input  logic [APB_ADDR_W-1:0]    paddr,
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [APB_DATA_W-1:0]    pwdata,
  output logic [APB_DATA_W-1:0]    prdata,
  output logic                     pready,
  output logic                     pslverr,

  output logic                     ddr_ck_t,
  output logic                     ddr_ck_c,
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
  input  logic                     ddr_alert_n,

  inout  wire [DDR_DQ_W-1:0]       ddr_dq,
  inout  wire [DDR_DM_W-1:0]       ddr_dqs_t,
  inout  wire [DDR_DM_W-1:0]       ddr_dqs_c,
  inout  wire [DDR_DM_W-1:0]       ddr_dm_n
);

  localparam logic [APB_ADDR_W-1:0] REG_CTRL   = 'h00;
  localparam logic [APB_ADDR_W-1:0] REG_STATUS = 'h04;
  localparam logic [APB_ADDR_W-1:0] REG_MR0    = 'h20;
  localparam logic [APB_ADDR_W-1:0] REG_MR1    = 'h24;
  localparam logic [APB_ADDR_W-1:0] REG_MR2    = 'h28;
  localparam logic [APB_ADDR_W-1:0] REG_MR3    = 'h2c;
  localparam logic [APB_ADDR_W-1:0] REG_MR4    = 'h30;
  localparam logic [APB_ADDR_W-1:0] REG_MR5    = 'h34;
  localparam logic [APB_ADDR_W-1:0] REG_MR6    = 'h38;

  typedef enum logic [3:0] {
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
    INIT_READY
  } init_state_e;

  typedef enum logic [3:0] {
    APP_IDLE,
    APP_ACT,
    APP_TRCD,
    APP_RD_CMD,
    APP_RD_WAIT,
    APP_RD_SEND,
    APP_WR_IGNORE,
    APP_WR_RESP
  } app_state_e;

  init_state_e init_state;
  app_state_e  app_state;

  logic        init_start;
  logic        init_done;
  logic [16:0] mr [0:6];
  logic [9:0]  wait_cnt;
  logic [9:0]  app_wait_cnt;
  logic        apb_wr;
  logic        apb_rd;

  logic [AXI_ADDR_W-1:0] rd_base_addr;
  logic [AXI_ADDR_W-1:0] rd_cur_addr;
  logic [7:0]            rd_len;
  logic [7:0]            rd_idx;
  logic [2:0]            rd_size;
  logic [1:0]            rd_burst;

  logic phy_rd_start;
  logic phy_rd_busy;
  logic phy_rd_valid;
  logic [DDR_DQ_W*DDR_BL8_UI-1:0] phy_rd_data;

  logic phy_wr_start;
  logic phy_wr_busy;
  logic phy_wr_done;
  logic [DDR_DQ_W*DDR_BL8_UI-1:0] phy_wr_data;
  logic [DDR_DM_W*DDR_BL8_UI-1:0] phy_wr_dm_n;

  logic [DDR_DQ_W-1:0] phy_dq_in;
  logic [DDR_DQ_W-1:0] phy_dq_out;
  logic                phy_dq_oe;
  logic [DDR_DM_W-1:0] phy_dm_out;
  logic                phy_dm_oe;
  logic [DDR_DM_W-1:0] phy_dqs_t_out;
  logic [DDR_DM_W-1:0] phy_dqs_c_out;
  logic                phy_dqs_oe;

  assign ddr_ck_t  = clk;
  assign ddr_ck_c  = ~clk;
  assign apb_wr    = psel & penable & pwrite;
  assign apb_rd    = psel & penable & ~pwrite;
  assign pready    = psel & penable;
  assign pslverr   = 1'b0;
  assign phy_dq_in = ddr_dq;

  // Top-level tri-state mapping.  In ASIC/FPGA implementation, replace this boundary
  // with technology I/O cells.  Internal RTL uses explicit data/OE signals.
  assign ddr_dq    = phy_dq_oe  ? phy_dq_out    : 'z;
  assign ddr_dm_n  = phy_dm_oe  ? phy_dm_out    : 'z;
  assign ddr_dqs_t = phy_dqs_oe ? phy_dqs_t_out : 'z;
  assign ddr_dqs_c = phy_dqs_oe ? phy_dqs_c_out : 'z;

  function automatic logic [AXI_ADDR_W-1:0] axi_next_addr(
    input logic [AXI_ADDR_W-1:0] base,
    input logic [AXI_ADDR_W-1:0] cur,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    logic [AXI_ADDR_W-1:0] beat_bytes;
    logic [AXI_ADDR_W-1:0] wrap_bytes;
    logic [AXI_ADDR_W-1:0] wrap_mask;
    logic [AXI_ADDR_W-1:0] next_linear;
    begin
      beat_bytes  = {{(AXI_ADDR_W-1){1'b0}}, 1'b1} << size;
      wrap_bytes  = beat_bytes * ({{(AXI_ADDR_W-8){1'b0}}, len} + {{(AXI_ADDR_W-1){1'b0}}, 1'b1});
      wrap_mask   = wrap_bytes - {{(AXI_ADDR_W-1){1'b0}}, 1'b1};
      next_linear = cur + beat_bytes;
      unique case (burst)
        2'b00: axi_next_addr = cur; // FIXED
        2'b01: axi_next_addr = next_linear; // INCR
        2'b10: axi_next_addr = (base & ~wrap_mask) | (next_linear & wrap_mask); // WRAP
        default: axi_next_addr = next_linear;
      endcase
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      init_start <= 1'b0;
      mr[0] <= 17'h0000;
      mr[1] <= 17'h0001;
      mr[2] <= 17'h0002;
      mr[3] <= 17'h0003;
      mr[4] <= 17'h0004;
      mr[5] <= 17'h0005;
      mr[6] <= 17'h0006;
    end else if (apb_wr) begin
      unique case (paddr)
        REG_CTRL: init_start <= pwdata[0];
        REG_MR0:  mr[0] <= pwdata[16:0];
        REG_MR1:  mr[1] <= pwdata[16:0];
        REG_MR2:  mr[2] <= pwdata[16:0];
        REG_MR3:  mr[3] <= pwdata[16:0];
        REG_MR4:  mr[4] <= pwdata[16:0];
        REG_MR5:  mr[5] <= pwdata[16:0];
        REG_MR6:  mr[6] <= pwdata[16:0];
        default: ;
      endcase
    end
  end

  always_comb begin
    prdata = '0;
    if (apb_rd) begin
      unique case (paddr)
        REG_CTRL:   prdata = {{(APB_DATA_W-1){1'b0}}, init_start};
        REG_STATUS: prdata = {{(APB_DATA_W-2){1'b0}}, ddr_alert_n, init_done};
        REG_MR0:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[0]};
        REG_MR1:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[1]};
        REG_MR2:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[2]};
        REG_MR3:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[3]};
        REG_MR4:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[4]};
        REG_MR5:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[5]};
        REG_MR6:    prdata = {{(APB_DATA_W-17){1'b0}}, mr[6]};
        default:    prdata = '0;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      init_state   <= INIT_RESET;
      app_state    <= APP_IDLE;
      wait_cnt     <= '0;
      app_wait_cnt <= '0;
      init_done    <= 1'b0;
      ddr_reset_n  <= 1'b0;
      ddr_cke      <= 1'b0;
      ddr_odt      <= 1'b0;
      ddr_par      <= 1'b0;
      ddr_cs_n     <= 1'b1;
      ddr_act_n    <= 1'b1;
      ddr_ras_n    <= 1'b1;
      ddr_cas_n    <= 1'b1;
      ddr_we_n     <= 1'b1;
      ddr_bg       <= '0;
      ddr_ba       <= '0;
      ddr_a        <= '0;
      rd_base_addr <= '0;
      rd_cur_addr  <= '0;
      rd_len       <= '0;
      rd_idx       <= '0;
      rd_size      <= '0;
      rd_burst     <= '0;
      phy_rd_start <= 1'b0;
      phy_wr_start <= 1'b0;
      phy_wr_data  <= '0;
      phy_wr_dm_n  <= '1;
      s_axi_rdata  <= '0;
      s_axi_rresp  <= 2'b00;
      s_axi_rlast  <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_bresp  <= 2'b00;
      s_axi_bvalid <= 1'b0;
    end else begin
      ddr_cs_n     <= 1'b1;
      ddr_act_n    <= 1'b1;
      ddr_ras_n    <= 1'b1;
      ddr_cas_n    <= 1'b1;
      ddr_we_n     <= 1'b1;
      ddr_bg       <= '0;
      ddr_ba       <= '0;
      ddr_a        <= '0;
      ddr_odt      <= 1'b0;
      ddr_par      <= 1'b0;
      phy_rd_start <= 1'b0;
      phy_wr_start <= 1'b0;

      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (!init_done) begin
        unique case (init_state)
          INIT_RESET: begin
            ddr_reset_n <= 1'b1;
            ddr_cke     <= 1'b0;
            if (init_start) begin
              init_state <= INIT_WAIT_CKE;
              wait_cnt   <= 10'd16;
            end
          end
          INIT_WAIT_CKE: begin
            if (wait_cnt != 0) begin
              wait_cnt <= wait_cnt - 1'b1;
            end else begin
              ddr_cke    <= 1'b1;
              init_state <= INIT_MR3;
            end
          end
          INIT_MR3: begin
            ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd3; ddr_bg <= '0; ddr_a <= mr[3];
            init_state <= INIT_MR6; wait_cnt <= T_MRD_CK[9:0];
          end
          INIT_MR6: begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd2; ddr_bg <= {{(DDR_BG_W-1){1'b0}},1'b1}; ddr_a <= mr[6]; init_state <= INIT_MR5; wait_cnt <= T_MRD_CK[9:0]; end
          end
          INIT_MR5: begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd1; ddr_bg <= {{(DDR_BG_W-1){1'b0}},1'b1}; ddr_a <= mr[5]; init_state <= INIT_MR4; wait_cnt <= T_MRD_CK[9:0]; end
          end
          INIT_MR4: begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd0; ddr_bg <= {{(DDR_BG_W-1){1'b0}},1'b1}; ddr_a <= mr[4]; init_state <= INIT_MR2; wait_cnt <= T_MRD_CK[9:0]; end
          end
          INIT_MR2: begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd2; ddr_bg <= '0; ddr_a <= mr[2]; init_state <= INIT_MR1; wait_cnt <= T_MRD_CK[9:0]; end
          end
          INIT_MR1: begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd1; ddr_bg <= '0; ddr_a <= mr[1]; init_state <= INIT_MR0; wait_cnt <= T_MRD_CK[9:0]; end
          end
          INIT_MR0: begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin ddr_cs_n <= 1'b0; ddr_act_n <= 1'b1; ddr_ras_n <= 1'b0; ddr_cas_n <= 1'b1; ddr_we_n <= 1'b1; ddr_ba <= 2'd0; ddr_bg <= '0; ddr_a <= mr[0]; init_state <= INIT_ZQCL; wait_cnt <= T_MOD_CK[9:0]; end
          end
          INIT_ZQCL: begin
            if (wait_cnt != 0) begin
              wait_cnt <= wait_cnt - 1'b1;
            end else begin
              ddr_cs_n  <= 1'b0;
              ddr_act_n <= 1'b1;
              ddr_ras_n <= 1'b0;
              ddr_cas_n <= 1'b0;
              ddr_we_n  <= 1'b1;
              ddr_a     <= 17'h00400;
              init_state <= INIT_READY;
            end
          end
          INIT_READY: begin
            init_done <= 1'b1;
            ddr_cke   <= 1'b1;
          end
          default: init_state <= INIT_RESET;
        endcase
      end else begin
        ddr_reset_n <= 1'b1;
        ddr_cke     <= 1'b1;

        unique case (app_state)
          APP_IDLE: begin
            if (s_axi_arvalid) begin
              rd_base_addr <= s_axi_araddr;
              rd_cur_addr  <= s_axi_araddr;
              rd_len       <= s_axi_arlen;
              rd_idx       <= 8'd0;
              rd_size      <= s_axi_arsize;
              rd_burst     <= s_axi_arburst;
              app_state    <= APP_ACT;
            end else if (s_axi_awvalid && s_axi_wvalid) begin
              app_state <= APP_WR_IGNORE;
            end
          end

          APP_ACT: begin
            ddr_cs_n  <= 1'b0;
            ddr_act_n <= 1'b0;
            ddr_ras_n <= rd_cur_addr[16];
            ddr_cas_n <= rd_cur_addr[15];
            ddr_we_n  <= rd_cur_addr[14];
            ddr_bg    <= rd_cur_addr[25 +: DDR_BG_W];
            ddr_ba    <= rd_cur_addr[23 +: DDR_BA_W];
            ddr_a     <= {2'b00, rd_cur_addr[22:8]};
            app_wait_cnt <= T_RCD_CK[9:0];
            app_state <= APP_TRCD;
          end

          APP_TRCD: begin
            if (app_wait_cnt != 0) begin
              app_wait_cnt <= app_wait_cnt - 1'b1;
            end else begin
              app_state <= APP_RD_CMD;
            end
          end

          APP_RD_CMD: begin
            ddr_cs_n  <= 1'b0;
            ddr_act_n <= 1'b1;
            ddr_ras_n <= 1'b1;
            ddr_cas_n <= 1'b0;
            ddr_we_n  <= 1'b1;
            ddr_bg    <= rd_cur_addr[25 +: DDR_BG_W];
            ddr_ba    <= rd_cur_addr[23 +: DDR_BA_W];
            ddr_a     <= '0;
            ddr_a[9:0] <= rd_cur_addr[11:2];
            ddr_a[10]  <= 1'b0;
            ddr_a[12]  <= 1'b1;
            phy_rd_start <= 1'b1;
            app_state <= APP_RD_WAIT;
          end

          APP_RD_WAIT: begin
            if (phy_rd_valid) begin
              s_axi_rdata  <= phy_rd_data[AXI_DATA_W-1:0];
              s_axi_rresp  <= 2'b00;
              s_axi_rlast  <= (rd_idx == rd_len);
              s_axi_rvalid <= 1'b1;
              app_state    <= APP_RD_SEND;
            end
          end

          APP_RD_SEND: begin
            if (s_axi_rvalid && s_axi_rready) begin
              s_axi_rvalid <= 1'b0;
              s_axi_rlast  <= 1'b0;
              if (rd_idx == rd_len) begin
                app_state <= APP_IDLE;
              end else begin
                rd_idx      <= rd_idx + 8'd1;
                rd_cur_addr <= axi_next_addr(rd_base_addr, rd_cur_addr, rd_len, rd_size, rd_burst);
                app_state   <= APP_ACT;
              end
            end
          end

          APP_WR_IGNORE: begin
            s_axi_bresp  <= 2'b00;
            s_axi_bvalid <= 1'b1;
            app_state    <= APP_WR_RESP;
          end

          APP_WR_RESP: begin
            if (s_axi_bvalid && s_axi_bready) begin
              s_axi_bvalid <= 1'b0;
              app_state    <= APP_IDLE;
            end
          end

          default: app_state <= APP_IDLE;
        endcase
      end
    end
  end

  assign s_axi_arready = init_done && (app_state == APP_IDLE);
  assign s_axi_awready = init_done && (app_state == APP_IDLE);
  assign s_axi_wready  = init_done && (app_state == APP_IDLE);

  ddr4_dq_dqs_phy #(
    .DQ_W(DDR_DQ_W),
    .DM_W(DDR_DM_W),
    .BURST_UI(DDR_BL8_UI),
    .CL_CK(T_CL_CK),
    .CWL_CK(T_CWL_CK)
  ) u_dq_dqs_phy (
    .clk       (clk),
    .rst_n     (rst_n),
    .wr_start  (phy_wr_start),
    .wr_data   (phy_wr_data),
    .wr_dm_n   (phy_wr_dm_n),
    .wr_busy   (phy_wr_busy),
    .wr_done   (phy_wr_done),
    .rd_start  (phy_rd_start),
    .rd_data   (phy_rd_data),
    .rd_valid  (phy_rd_valid),
    .rd_busy   (phy_rd_busy),
    .dq_in     (phy_dq_in),
    .dq_out    (phy_dq_out),
    .dq_oe     (phy_dq_oe),
    .dm_out    (phy_dm_out),
    .dm_oe     (phy_dm_oe),
    .dqs_t_out (phy_dqs_t_out),
    .dqs_c_out (phy_dqs_c_out),
    .dqs_oe    (phy_dqs_oe)
  );

endmodule : ddr4_controller_top
