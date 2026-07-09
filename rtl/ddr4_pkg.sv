package ddr4_pkg;
  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 32;
  parameter int APB_ADDR_W = 32;
  parameter int APB_DATA_W = 32;

  parameter int AXI_AW_FIFO_DEPTH = 8;
  parameter int AXI_AR_FIFO_DEPTH = 8;
  parameter int REQ_FIFO_DEPTH    = 16;
  parameter int RSP_FIFO_DEPTH    = 16;
  parameter int CACHE_LINES       = 64;

  // V2.1 clocking: AXI/APB 200MHz, DRAM controller/PHY 500MHz, asynchronous domains.
  parameter int AXI_CLK_MHZ  = 200;
  parameter int DRAM_CLK_MHZ = 500;

  parameter int DDR4_DQ_W   = 16;
  parameter int DDR4_DQS_W  = DDR4_DQ_W/8;
  parameter int DDR4_ADDR_W = 17;
  parameter int DDR4_BA_W   = 2;
  parameter int DDR4_BG_W   = 2;
  parameter int DDR4_ROW_W  = 15;
  parameter int DDR4_COL_W  = 10;
  parameter int DDR4_BL     = 8;

  parameter int T_RCD_CK = 8;
  parameter int T_RP_CK  = 8;
  parameter int T_RAS_CK = 18;
  parameter int T_RFC_CK = 180;
  parameter int T_REFI_CK = 3900;
  parameter int CL_CK    = 16;
  parameter int CWL_CK   = 12;
  parameter int INIT_CK  = 64;

  typedef enum logic [3:0] {
    DDR4_CMD_DES = 4'd0,
    DDR4_CMD_ACT = 4'd1,
    DDR4_CMD_RD  = 4'd2,
    DDR4_CMD_WR  = 4'd3,
    DDR4_CMD_PRE = 4'd4,
    DDR4_CMD_REF = 4'd5,
    DDR4_CMD_MRS = 4'd6,
    DDR4_CMD_ZQCL= 4'd7
  } ddr4_cmd_e;

  typedef struct packed {
    logic                 wr;
    logic [AXI_ADDR_W-1:0] addr;
    logic [AXI_DATA_W-1:0] wdata;
    logic [AXI_DATA_W/8-1:0] wstrb;
  } req_t;

  typedef struct packed {
    logic                 wr;
    logic [AXI_ADDR_W-1:0] addr;
    logic [AXI_DATA_W-1:0] rdata;
    logic [1:0]           resp;
  } rsp_t;
endpackage
