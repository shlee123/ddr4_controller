// SPDX-License-Identifier: MIT
// DDR4 controller top-level, first RTL skeleton connected to Micron 4Gb DDR4 command bus.

import ddr4_ctrl_pkg::*;

module ddr4_controller_top #(
  parameter int AXI_ADDR_W = 32,
  parameter int AXI_DATA_W = 32,
  parameter int APB_ADDR_W = 32,
  parameter int APB_DATA_W = 32,
  parameter int DDR_ADDR_W = 17,
  parameter int DDR_BG_W   = 2,
  parameter int DDR_BA_W   = 2,
  parameter int DDR_DQ_W   = 16
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // AXI4 write address channel
  input  logic [AXI_ADDR_W-1:0]    s_axi_awaddr,
  input  logic [7:0]               s_axi_awlen,
  input  logic [2:0]               s_axi_awsize,
  input  logic [1:0]               s_axi_awburst,
  input  logic                     s_axi_awvalid,
  output logic                     s_axi_awready,

  // AXI4 write data channel
  input  logic [AXI_DATA_W-1:0]    s_axi_wdata,
  input  logic [AXI_DATA_W/8-1:0]  s_axi_wstrb,
  input  logic                     s_axi_wlast,
  input  logic                     s_axi_wvalid,
  output logic                     s_axi_wready,

  // AXI4 write response channel
  output logic [1:0]               s_axi_bresp,
  output logic                     s_axi_bvalid,
  input  logic                     s_axi_bready,

  // AXI4 read address channel
  input  logic [AXI_ADDR_W-1:0]    s_axi_araddr,
  input  logic [7:0]               s_axi_arlen,
  input  logic [2:0]               s_axi_arsize,
  input  logic [1:0]               s_axi_arburst,
  input  logic                     s_axi_arvalid,
  output logic                     s_axi_arready,

  // AXI4 read data channel
  output logic [AXI_DATA_W-1:0]    s_axi_rdata,
  output logic [1:0]               s_axi_rresp,
  output logic                     s_axi_rlast,
  output logic                     s_axi_rvalid,
  input  logic                     s_axi_rready,

  // APB slave interface
  input  logic [APB_ADDR_W-1:0]    paddr,
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [APB_DATA_W-1:0]    pwdata,
  output logic [APB_DATA_W-1:0]    prdata,
  output logic                     pready,
  output logic                     pslverr,

  // DDR4 command/address interface.  Data pins will be added to the controller after PHY boundary is fixed.
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
  input  logic                     ddr_alert_n
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

  init_state_e init_state;
  logic        init_start;
  logic        init_done;
  logic [16:0] mr [0:6];
  logic [9:0]  wait_cnt;
  logic        apb_wr;
  logic        apb_rd;

  assign ddr_ck_t = clk;
  assign ddr_ck_c = ~clk;
  assign apb_wr   = psel & penable & pwrite;
  assign apb_rd   = psel & penable & ~pwrite;
  assign pready   = psel & penable;
  assign pslverr  = 1'b0;

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
      ddr_cs_n  = 1'b1;
      ddr_act_n = 1'b1;
      ddr_ras_n = 1'b1;
      ddr_cas_n = 1'b1;
      ddr_we_n  = 1'b1;
      ddr_a     = '0;
      ddr_ba    = '0;
      ddr_bg    = '0;
    end
  endtask

  task automatic drive_mrs(input logic [2:0] mr_idx, input logic [16:0] value);
    begin
      ddr_cs_n  = 1'b0;
      ddr_act_n = 1'b1;
      ddr_ras_n = 1'b0;
      ddr_cas_n = 1'b1;
      ddr_we_n  = 1'b1;
      ddr_ba    = mr_idx[1:0];
      ddr_bg    = {{(DDR_BG_W-1){1'b0}}, mr_idx[2]};
      ddr_a     = value;
    end
  endtask

  task automatic drive_zqcl;
    begin
      ddr_cs_n  = 1'b0;
      ddr_act_n = 1'b1;
      ddr_ras_n = 1'b0;
      ddr_cas_n = 1'b0;
      ddr_we_n  = 1'b1;
      ddr_a     = 17'h00400; // A10 = 1 for ZQCL in this first model
      ddr_ba    = '0;
      ddr_bg    = '0;
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      init_state  <= INIT_RESET;
      wait_cnt    <= '0;
      init_done   <= 1'b0;
      ddr_reset_n <= 1'b0;
      ddr_cke     <= 1'b0;
      ddr_odt     <= 1'b0;
      ddr_par     <= 1'b0;
      drive_des();
    end else begin
      drive_des();
      ddr_odt <= 1'b0;
      ddr_par <= 1'b0;

      unique case (init_state)
        INIT_RESET: begin
          ddr_reset_n <= 1'b1;
          ddr_cke     <= 1'b0;
          init_done   <= 1'b0;
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

        INIT_MR3: begin drive_mrs(3'd3, mr[3]); init_state <= INIT_MR6; wait_cnt <= T_MRD_CK[9:0]; end
        INIT_MR6: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd6, mr[6]); init_state <= INIT_MR5; wait_cnt <= T_MRD_CK[9:0]; end end
        INIT_MR5: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd5, mr[5]); init_state <= INIT_MR4; wait_cnt <= T_MRD_CK[9:0]; end end
        INIT_MR4: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd4, mr[4]); init_state <= INIT_MR2; wait_cnt <= T_MRD_CK[9:0]; end end
        INIT_MR2: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd2, mr[2]); init_state <= INIT_MR1; wait_cnt <= T_MRD_CK[9:0]; end end
        INIT_MR1: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd1, mr[1]); init_state <= INIT_MR0; wait_cnt <= T_MRD_CK[9:0]; end end
        INIT_MR0: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_mrs(3'd0, mr[0]); init_state <= INIT_ZQCL; wait_cnt <= T_MOD_CK[9:0]; end end
        INIT_ZQCL: begin if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1; else begin drive_zqcl(); init_state <= INIT_READY; end end

        INIT_READY: begin
          init_done <= 1'b1;
          ddr_cke   <= 1'b1;
        end

        default: init_state <= INIT_RESET;
      endcase
    end
  end

  // AXI frontend is intentionally held off until DDR scheduler/data path is added.
  assign s_axi_awready = init_done;
  assign s_axi_wready  = init_done;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_bvalid  = 1'b0;
  assign s_axi_arready = init_done;
  assign s_axi_rdata   = '0;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rlast   = 1'b0;
  assign s_axi_rvalid  = 1'b0;

endmodule : ddr4_controller_top
