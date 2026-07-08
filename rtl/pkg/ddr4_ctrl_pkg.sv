// SPDX-License-Identifier: MIT
// DDR4 controller common package.
// Compile this file once before RTL modules. Do not `include this package in RTL files.

package ddr4_ctrl_pkg;

  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 32;
  parameter int APB_ADDR_W = 32;
  parameter int APB_DATA_W = 32;

  parameter int DDR_ROW_W  = 16;
  parameter int DDR_COL_W  = 10;
  parameter int DDR_BANK_W = 3;
  parameter int DDR_BG_W   = 2;

  typedef enum logic [3:0] {
    DDR_CMD_NOP  = 4'h0,
    DDR_CMD_ACT  = 4'h1,
    DDR_CMD_RD   = 4'h2,
    DDR_CMD_WR   = 4'h3,
    DDR_CMD_PRE  = 4'h4,
    DDR_CMD_REF  = 4'h5,
    DDR_CMD_MRS  = 4'h6,
    DDR_CMD_ZQCL = 4'h7
  } ddr_cmd_e;

  typedef struct packed {
    logic [AXI_ADDR_W-1:0] addr;
    logic                 write;
    logic [7:0]           len;
    logic [2:0]           size;
    logic [1:0]           burst;
  } axi_req_t;

  typedef struct packed {
    logic [DDR_BG_W-1:0]   bg;
    logic [DDR_BANK_W-1:0] bank;
    logic [DDR_ROW_W-1:0]  row;
    logic [DDR_COL_W-1:0]  col;
  } ddr_addr_t;

endpackage : ddr4_ctrl_pkg
