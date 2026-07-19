`timescale 1ns/1ps

module tb_ddr4_controller_production;
  import ddr4_ctrl_pkg::*;

  localparam int AXI_ADDR_W = 32;
  localparam int AXI_DATA_W = 32;
  localparam int APB_ADDR_W = 32;
  localparam int APB_DATA_W = 32;
  localparam int DDR_ADDR_W = 17;
  localparam int DDR_BG_W   = 2;
  localparam int DDR_BA_W   = 2;
  localparam int DDR_DQ_W   = 16;
  localparam int DDR_DM_W   = DDR_DQ_W/8;

  localparam logic [APB_ADDR_W-1:0] REG_STATUS = 32'h0000_0004;
  localparam int INIT_TIMEOUT_AXI_CYCLES = 5000;

  logic axi_clk;
  logic axi_rst_n;
  logic ddr_clk;
  logic ddr_rst_n;

  logic [AXI_ADDR_W-1:0]   s_axi_awaddr;
  logic [7:0]              s_axi_awlen;
  logic [2:0]              s_axi_awsize;
  logic [1:0]              s_axi_awburst;
  logic                    s_axi_awvalid;
  logic                    s_axi_awready;
  logic [AXI_DATA_W-1:0]   s_axi_wdata;
  logic [AXI_DATA_W/8-1:0] s_axi_wstrb;
  logic                    s_axi_wlast;
  logic                    s_axi_wvalid;
  logic                    s_axi_wready;
  logic [1:0]              s_axi_bresp;
  logic                    s_axi_bvalid;
  logic                    s_axi_bready;
  logic [AXI_ADDR_W-1:0]   s_axi_araddr;
  logic [7:0]              s_axi_arlen;
  logic [2:0]              s_axi_arsize;
  logic [1:0]              s_axi_arburst;
  logic                    s_axi_arvalid;
  logic                    s_axi_arready;
  logic [AXI_DATA_W-1:0]   s_axi_rdata;
  logic [1:0]              s_axi_rresp;
  logic                    s_axi_rlast;
  logic                    s_axi_rvalid;
  logic                    s_axi_rready;

  logic [APB_ADDR_W-1:0]   paddr;
  logic                    psel;
  logic                    penable;
  logic                    pwrite;
  logic [APB_DATA_W-1:0]   pwdata;
  logic [APB_DATA_W-1:0]   prdata;
  logic                    pready;
  logic                    pslverr;

  logic                    ddr_ck_t;
  logic                    ddr_ck_c;
  logic                    ddr_reset_n;
  logic                    ddr_cke;
  logic                    ddr_cs_n;
  logic                    ddr_act_n;
  logic                    ddr_ras_n;
  logic                    ddr_cas_n;
  logic                    ddr_we_n;
  logic [DDR_BG_W-1:0]     ddr_bg;
  logic [DDR_BA_W-1:0]     ddr_ba;
  logic [DDR_ADDR_W-1:0]   ddr_a;
  logic                    ddr_odt;
  logic                    ddr_par;
  logic                    ddr_alert_n;
  wire [DDR_DQ_W-1:0]      ddr_dq;
  wire [DDR_DM_W-1:0]      ddr_dqs_t;
  wire [DDR_DM_W-1:0]      ddr_dqs_c;
  wire [DDR_DM_W-1:0]      ddr_dm_n;

  integer act_count;
  integer mrs_count;
  integer zq_count;

  // 200 MHz AXI/APB domain and 500 MHz DDR/controller domain.
  initial begin
    axi_clk = 1'b0;
    forever #2.5 axi_clk = ~axi_clk;
  end

  initial begin
    ddr_clk = 1'b0;
    forever #1.0 ddr_clk = ~ddr_clk;
  end

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W),
    .APB_DATA_W(APB_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W),
    .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W),
    .DDR_DQ_W(DDR_DQ_W),
    .DDR_DM_W(DDR_DM_W)
  ) dut (
    .axi_clk(axi_clk),
    .axi_rst_n(axi_rst_n),
    .clk(ddr_clk),
    .rst_n(ddr_rst_n),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .paddr(paddr),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .pwdata(pwdata),
    .prdata(prdata),
    .pready(pready),
    .pslverr(pslverr),
    .ddr_ck_t(ddr_ck_t),
    .ddr_ck_c(ddr_ck_c),
    .ddr_reset_n(ddr_reset_n),
    .ddr_cke(ddr_cke),
    .ddr_cs_n(ddr_cs_n),
    .ddr_act_n(ddr_act_n),
    .ddr_ras_n(ddr_ras_n),
    .ddr_cas_n(ddr_cas_n),
    .ddr_we_n(ddr_we_n),
    .ddr_bg(ddr_bg),
    .ddr_ba(ddr_ba),
    .ddr_a(ddr_a),
    .ddr_odt(ddr_odt),
    .ddr_par(ddr_par),
    .ddr_alert_n(ddr_alert_n),
    .ddr_dq(ddr_dq),
    .ddr_dqs_t(ddr_dqs_t),
    .ddr_dqs_c(ddr_dqs_c),
    .ddr_dm_n(ddr_dm_n)
  );

  ddr4_sdram_model #(
    .DQ_W(DDR_DQ_W),
    .ADDR_W(DDR_ADDR_W),
    .BA_W(DDR_BA_W),
    .BG_W(DDR_BG_W)
  ) dram (
    .reset_n(ddr_reset_n),
    .ck_t(ddr_ck_t),
    .ck_c(ddr_ck_c),
    .cke(ddr_cke),
    .cs_n(ddr_cs_n),
    .act_n(ddr_act_n),
    .ras_n(ddr_ras_n),
    .cas_n(ddr_cas_n),
    .we_n(ddr_we_n),
    .a(ddr_a),
    .ba(ddr_ba),
    .bg(ddr_bg),
    .odt(ddr_odt),
    .dq(ddr_dq),
    .dqs_t(ddr_dqs_t),
    .dqs_c(ddr_dqs_c),
    .dm_n(ddr_dm_n),
    .alert_n(ddr_alert_n)
  );

  task automatic apb_read(
    input  logic [APB_ADDR_W-1:0] addr,
    output logic [APB_DATA_W-1:0] data
  );
    begin
      @(posedge axi_clk);
      paddr   <= addr;
      pwrite  <= 1'b0;
      psel    <= 1'b1;
      penable <= 1'b0;
      @(posedge axi_clk);
      penable <= 1'b1;
      while (!pready) @(posedge axi_clk);
      data = prdata;
      @(posedge axi_clk);
      psel    <= 1'b0;
      penable <= 1'b0;
      paddr   <= '0;
    end
  endtask

  always @(posedge ddr_ck_t) begin
    if (ddr_reset_n && ddr_cke && !ddr_cs_n) begin
      if (!ddr_act_n) begin
        act_count = act_count + 1;
      end else begin
        case ({ddr_ras_n, ddr_cas_n, ddr_we_n})
          3'b011: mrs_count = mrs_count + 1;
          3'b001: zq_count  = zq_count + 1;
          default: ;
        endcase
      end
    end
  end

  initial begin : test_sequence
    logic [APB_DATA_W-1:0] status;
    integer cycles;

    axi_rst_n = 1'b0;
    ddr_rst_n = 1'b0;
    s_axi_awaddr  = '0;
    s_axi_awlen   = '0;
    s_axi_awsize  = 3'd2;
    s_axi_awburst = 2'b01;
    s_axi_awvalid = 1'b0;
    s_axi_wdata   = '0;
    s_axi_wstrb   = '0;
    s_axi_wlast   = 1'b0;
    s_axi_wvalid  = 1'b0;
    s_axi_bready  = 1'b1;
    s_axi_araddr  = '0;
    s_axi_arlen   = '0;
    s_axi_arsize  = 3'd2;
    s_axi_arburst = 2'b01;
    s_axi_arvalid = 1'b0;
    s_axi_rready  = 1'b1;
    paddr         = '0;
    psel          = 1'b0;
    penable       = 1'b0;
    pwrite        = 1'b0;
    pwdata        = '0;
    act_count     = 0;
    mrs_count     = 0;
    zq_count      = 0;

    repeat (8) @(posedge axi_clk);
    axi_rst_n = 1'b1;
    repeat (8) @(posedge ddr_clk);
    ddr_rst_n = 1'b1;

    status = '0;
    cycles = 0;
    while (!status[0] && cycles < INIT_TIMEOUT_AXI_CYCLES) begin
      apb_read(REG_STATUS, status);
      if (pslverr) $fatal(1, "APB status access returned PSLVERR");
      cycles = cycles + 1;
    end

    if (!status[0]) begin
      $fatal(1, "Timeout waiting for production controller init_done");
    end
    if (!status[1]) begin
      $fatal(1, "DDR4 model asserted alert_n low during initialization");
    end
    if (mrs_count < 7) begin
      $fatal(1, "Expected at least 7 MRS commands, observed %0d", mrs_count);
    end
    if (zq_count < 1) begin
      $fatal(1, "Expected a ZQCL command, observed %0d", zq_count);
    end
    if (s_axi_bvalid || s_axi_rvalid) begin
      $fatal(1, "Unexpected AXI response while AXI request channels were idle");
    end

    $display("PASS production initialization: cycles=%0d mrs=%0d zq=%0d act=%0d", cycles, mrs_count, zq_count, act_count);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "Global production regression timeout");
  end

endmodule
