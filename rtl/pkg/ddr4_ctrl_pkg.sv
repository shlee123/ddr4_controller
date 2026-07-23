// SPDX-License-Identifier: MIT
// DDR4 controller common package.
// Compile this file once before RTL modules. Do not `include this package in RTL files.

`timescale 1ns/1ps

package ddr4_ctrl_pkg;

  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 32;
  parameter int AXI_ID_W   = 6;
  parameter int APB_ADDR_W = 32;
  parameter int APB_DATA_W = 32;

  parameter int AXI_CLK_MHZ  = 200;
  parameter int DDR_CLK_MHZ  = 500;

  parameter int AXI_AW_FIFO_DEPTH = 8;
  parameter int AXI_W_FIFO_DEPTH  = 8;
  parameter int AXI_AR_FIFO_DEPTH = 8;
  parameter int REQ_FIFO_DEPTH    = 16;
  parameter int RSP_FIFO_DEPTH    = 16;
  parameter int CACHE_LINES       = 64;
  parameter int WRITE_BUFFER_DEPTH = 32;
  parameter int VICTIM_CACHE_LINES = 16;

  parameter int DDR_ADDR_W = 17;
  parameter int DDR_ROW_W  = 15;
  parameter int DDR_COL_W  = 10;
  parameter int DDR_BANK_W = 2;
  parameter int DDR_BG_W   = 2;
  parameter int DDR_DQ_W   = 16;
  parameter int DDR_DM_W   = DDR_DQ_W / 8;
  parameter int DDR_BL8_UI = 8;
  parameter int DDR_BURST_DATA_W = DDR_DQ_W * DDR_BL8_UI;
  parameter int DDR_BURST_DM_W   = DDR_DM_W * DDR_BL8_UI;

  typedef enum logic [4:0] {
    DDR_CMD_DES=5'h00, DDR_CMD_NOP=5'h01, DDR_CMD_ACT=5'h02,
    DDR_CMD_RD=5'h03, DDR_CMD_RDA=5'h04, DDR_CMD_WR=5'h05,
    DDR_CMD_WRA=5'h06, DDR_CMD_PRE=5'h07, DDR_CMD_PREA=5'h08,
    DDR_CMD_REF=5'h09, DDR_CMD_MRS=5'h0a, DDR_CMD_ZQCL=5'h0b,
    DDR_CMD_ZQCS=5'h0c, DDR_CMD_SRE=5'h0d, DDR_CMD_SRX=5'h0e,
    DDR_CMD_PDE=5'h0f, DDR_CMD_PDX=5'h10, DDR_CMD_UNK=5'h1f
  } ddr_cmd_e;

  typedef enum logic [1:0] {
    DDR_BURST_FIXED=2'b00, DDR_BURST_INCR=2'b01, DDR_BURST_WRAP=2'b10
  } axi_burst_e;

  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_ADDR_W-1:0] addr;
    logic                  write;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
  } axi_req_t;

  typedef struct packed {
    logic [DDR_BG_W-1:0]   bg;
    logic [DDR_BANK_W-1:0] bank;
    logic [DDR_ROW_W-1:0]  row;
    logic [DDR_COL_W-1:0]  col;
  } ddr_addr_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]     id;
    logic                    wr;
    logic [AXI_ADDR_W-1:0]   addr;
    logic [AXI_DATA_W-1:0]   wdata;
    logic [AXI_DATA_W/8-1:0] wstrb;
    logic [7:0]              len;
    logic [2:0]              size;
    logic [1:0]              burst;
  } ddr_req_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic                  wr;
    logic [AXI_ADDR_W-1:0] addr;
    logic [AXI_DATA_W-1:0] rdata;
    logic [1:0]            resp;
    logic                  last;
  } ddr_rsp_t;

  parameter int T_RCD_CK=8, T_RP_CK=8, T_RAS_CK=18, T_RC_CK=26;
  parameter int T_MRD_CK=8, T_MOD_CK=24;
  parameter int T_DLLK_CK=768, T_ZQINIT_CK=1024;
  parameter int T_CL_CK=11, T_CWL_CK=9;

endpackage : ddr4_ctrl_pkg
