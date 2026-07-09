// SPDX-License-Identifier: MIT
// DDR4 controller top-level, Version 2.
// Adds controller-side DQ/DQS burst-data support through ddr4_dq_dqs_phy.

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
    APP_WR_CMD,
    APP_WR_DATA,
    APP_WR_RESP,
    APP_RD_CMD,
    APP_RD_DATA,
    APP_RD_RESP
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
  logic        app_is_write;
  logic [AXI_ADDR_W-1:0] app_addr;
  logic [AXI_DATA_W-1:0] app_wdata;
  logic [AXI_DATA_W/8-1:0] app_wstrb;

  logic phy_wr_start;
  logic phy_wr_busy;
  logic phy_wr_done;
  logic [DDR_DQ_W*DDR_BL8_UI-1:0] phy_wr_data;
  logic [DDR_DM_W*DDR_BL8_UI-1:0] phy_wr_dm_n;
  logic phy_rd_start;
  logic phy_rd_busy;
  logic phy_rd_valid;
  logic [DDR_DQ_W*DDR_BL8_UI-1:0] phy_rd_data;

  assign ddr_ck_t = clk;
  assign ddr_ck_c = ~clk;
  assign apb_wr   = psel & penable & pwrite;
  assign apb_rd   = psel & penable & ~pwrite;
  assign pready   = psel & penable;
  assign pslverr  = 1'b0;

  function automatic logic [DDR_DQ_W*DDR_BL8_UI-1:0] expand_axi_to_bl8(input logic [AXI_DATA_W-1:0] data);
    logic [DDR_DQ_W*DDR_BL8_UI-1:0] tmp;
    begin
      tmp = '0;
      for (int i = 0; i < DDR_BL8_UI; i++) begin
        tmp[i*DDR_DQ_W +: DDR_DQ_W] = data[(i % (AXI_DATA_W/DDR_DQ_W))*DDR_DQ_W +: DDR_DQ_W];
      end
      return tmp;
    end
  endfunction

  function automatic logic [DDR_DM_W*DDR_BL8_UI-1:0] expand_strb_to_dm_n(input logic [AXI_DATA_W/8-1:0] strb);
    logic [DDR_DM_W*DDR_BL8_UI-1:0] tmp;
    begin
      tmp = '1;
      for (int i = 0; i < DDR_BL8_UI; i++) begin
        tmp[i*DDR_DM_W +: DDR_DM_W] = ~strb[(i % (AXI_DATA_W/8/DDR_DM_W))*DDR_DM_W +: DDR_DM_W];
      end
      return tmp;
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

  task automatic drive_des;
    begin
      ddr_cs_n  <= 1'b1;
      ddr_act_n <= 1'b1;
      ddr_ras_n <= 1'b1;
      ddr_cas_n <= 1'b1;
      ddr_we_n  <= 1'b1;
      ddr_a     <= '0;
      ddr_ba    <= '0;
      ddr_bg    <= '0;
    end
  endtask

  task automatic drive_mrs(input logic [2:0] mr_idx, input logic [16:0] value);
    begin
      ddr_cs_n  <= 1'b0;
      ddr_act_n <= 1'b1;
      ddr_ras_n <= 1'b0;
      ddr_cas_n <= 1'b1;
      ddr_we_n  <= 1'b1;
      ddr_ba    <= mr_idx[1:0];
      ddr_bg    <= {{(DDR_BG_W-1){1'b0}}, mr_idx[2]};
      ddr_a     <= value;
    end
  endtask

  task automatic drive_zqcl;
    begin
      ddr_cs_n  <= 1'b0;
      ddr_act_n <= 1'b1;
      ddr_ras_n <= 1'b0;
      ddr_cas_n <= 1'b0;
      ddr_we_n  <= 1'b1;
      ddr_a     <= 17'h00400;
      ddr_ba    <= '0;
      ddr_bg    <= '0;
    end
  endtask

  task automatic drive_act(input logic [AXI_ADDR_W-1:0] addr);
    begin
      ddr_cs_n  <= 1'b0;
      ddr_act_n <= 1'b0;
      ddr_ras_n <= addr[16];
      ddr_cas_n <= addr[15];
      ddr_we_n  <= addr[14];
      ddr_bg    <= addr[25 +: DDR_BG_W];
      ddr_ba    <= addr[23 +: DDR_BA_W];
      ddr_a     <= {2'b00, addr[22:8]};
    end
  endtask

  task automatic drive_rdwr(input logic [AXI_ADDR_W-1:0] addr, input logic is_write);
    begin
      ddr_cs_n  <= 1'b0;
      ddr_act_n <= 1'b1;
      ddr_ras_n <= 1'b1;
      ddr_cas_n <= 1'b0;
      ddr_we_n  <= is_write ? 1'b0 : 1'b1;
      ddr_bg    <= addr[25 +: DDR_BG_W];
      ddr_ba    <= addr[23 +: DDR_BA_W];
      ddr_a     <= '0;
      ddr_a[9:0] <= addr[11:2];
      ddr_a[10]  <= 1'b0; // no auto-precharge in V2 simple path
      ddr_a[12]  <= 1'b1; // no burst chop: BL8
    end
  endtask

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
      phy_wr_start <= 1'b0;
      phy_rd_start <= 1'b0;
      s_axi_bvalid <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_rdata  <= '0;
      s_axi_rresp  <= 2'b00;
      s_axi_bresp  <= 2'b00;
      s_axi_rlast  <= 1'b0;
      app_addr     <= '0;
      app_wdata    <= '0;
      app_wstrb    <= '0;
      app_is_write <= 1'b0;
      drive_des();
    end else begin
      drive_des();
      ddr_odt      <= 1'b0;
      ddr_par      <= 1'b0;
      phy_wr_start <= 1'b0;
      phy_rd_start <= 1'b0;

      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
        s_axi_rlast  <= 1'b0;
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
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            else begin
              ddr_cke    <= 1'b1;
              init_state <= INIT_MR3;
            end
          end
          INIT_MR3:  begin drive_mrs(3'd3, mr[3]); init_state <= INIT_MR6;  wait_cnt <= T_MRD_CK[9:0]; end
          INIT_MR6:  begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd6, mr[6]); init_state <= INIT_MR5; wait_cnt <= T_MRD_CK[9:0]; end end
          INIT_MR5:  begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd5, mr[5]); init_state <= INIT_MR4; wait_cnt <= T_MRD_CK[9:0]; end end
          INIT_MR4:  begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd4, mr[4]); init_state <= INIT_MR2; wait_cnt <= T_MRD_CK[9:0]; end end
          INIT_MR2:  begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd2, mr[2]); init_state <= INIT_MR1; wait_cnt <= T_MRD_CK[9:0]; end end
          INIT_MR1:  begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd1, mr[1]); init_state <= INIT_MR0; wait_cnt <= T_MRD_CK[9:0]; end end
          INIT_MR0:  begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd0, mr[0]); init_state <= INIT_ZQCL; wait_cnt <= T_MOD_CK[9:0]; end end
          INIT_ZQCL: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_zqcl(); init_state <= INIT_READY; end end
          INIT_READY: begin init_done <= 1'b1; ddr_cke <= 1'b1; end
          default: init_state <= INIT_RESET;
        endcase
      end else begin
        ddr_cke <= 1'b1;
        unique case (app_state)
          APP_IDLE: begin
            if (s_axi_awvalid && s_axi_wvalid) begin
              app_addr     <= s_axi_awaddr;
              app_wdata    <= s_axi_wdata;
              app_wstrb    <= s_axi_wstrb;
              app_is_write <= 1'b1;
              app_state    <= APP_ACT;
            end else if (s_axi_arvalid) begin
              app_addr     <= s_axi_araddr;
              app_is_write <= 1'b0;
              app_state    <= APP_ACT;
            end
          end
          APP_ACT: begin
            drive_act(app_addr);
            app_wait_cnt <= T_RCD_CK[9:0];
            app_state <= APP_TRCD;
          end
          APP_TRCD: begin
            if (app_wait_cnt != 0) app_wait_cnt <= app_wait_cnt - 1'b1;
            else app_state <= app_is_write ? APP_WR_CMD : APP_RD_CMD;
          end
          APP_WR_CMD: begin
            drive_rdwr(app_addr, 1'b1);
            phy_wr_data  <= expand_axi_to_bl8(app_wdata);
            phy_wr_dm_n  <= expand_strb_to_dm_n(app_wstrb);
            phy_wr_start <= 1'b1;
            app_state    <= APP_WR_DATA;
          end
          APP_WR_DATA: begin
            if (phy_wr_done) app_state <= APP_WR_RESP;
          end
          APP_WR_RESP: begin
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= 2'b00;
            if (s_axi_bready) app_state <= APP_IDLE;
          end
          APP_RD_CMD: begin
            drive_rdwr(app_addr, 1'b0);
            phy_rd_start <= 1'b1;
            app_state    <= APP_RD_DATA;
          end
          APP_RD_DATA: begin
            if (phy_rd_valid) begin
              s_axi_rdata  <= phy_rd_data[AXI_DATA_W-1:0];
              s_axi_rresp  <= 2'b00;
              s_axi_rlast  <= 1'b1;
              s_axi_rvalid <= 1'b1;
              app_state    <= APP_RD_RESP;
            end
          end
          APP_RD_RESP: begin
            if (s_axi_rvalid && s_axi_rready) app_state <= APP_IDLE;
          end
          default: app_state <= APP_IDLE;
        endcase
      end
    end
  end

  assign s_axi_awready = init_done && (app_state == APP_IDLE);
  assign s_axi_wready  = init_done && (app_state == APP_IDLE);
  assign s_axi_arready = init_done && (app_state == APP_IDLE);

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
    .ddr_dq    (ddr_dq),
    .ddr_dqs_t (ddr_dqs_t),
    .ddr_dqs_c (ddr_dqs_c),
    .ddr_dm_n  (ddr_dm_n)
  );

endmodule : ddr4_controller_top
