// SPDX-License-Identifier: MIT

`timescale 1ns/1ps

module tb_ddr4_controller;

  localparam int AXI_ADDR_W = 32;
  localparam int AXI_DATA_W = 32;
  localparam int APB_ADDR_W = 32;
  localparam int APB_DATA_W = 32;
  localparam int DDR_ADDR_W = 17;
  localparam int DDR_BG_W   = 2;
  localparam int DDR_BA_W   = 2;
  localparam int DDR_DQ_W   = 16;

  logic clk;
  logic rst_n;

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

  logic                    psel;
  logic                    penable;
  logic                    pwrite;
  logic [APB_ADDR_W-1:0]   paddr;
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
  wire [DDR_DQ_W/8-1:0]    ddr_dqs_t;
  wire [DDR_DQ_W/8-1:0]    ddr_dqs_c;
  wire [DDR_DQ_W/8-1:0]    ddr_dm_n;

  initial clk = 1'b0;
  always #1 clk = ~clk; // 500 MHz controller clock

  task automatic apb_write(
    input logic [APB_ADDR_W-1:0] addr,
    input logic [APB_DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      paddr   <= addr;
      pwdata  <= data;
      pwrite  <= 1'b1;
      psel    <= 1'b1;
      penable <= 1'b0;
      @(posedge clk);
      penable <= 1'b1;
      @(posedge clk);
      psel    <= 1'b0;
      penable <= 1'b0;
      pwrite  <= 1'b0;
    end
  endtask

  task automatic axi_burst_read_check(
    input logic [AXI_ADDR_W-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    integer beat_count;
    integer timeout;
    begin
      beat_count = 0;
      timeout = 0;

      @(posedge clk);
      s_axi_araddr  <= addr;
      s_axi_arlen   <= len;
      s_axi_arsize  <= size;
      s_axi_arburst <= burst;
      s_axi_arvalid <= 1'b1;

      while (!s_axi_arready) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 2000) $fatal(1, "AXI AR timeout");
      end

      @(posedge clk);
      s_axi_arvalid <= 1'b0;
      timeout = 0;

      while (beat_count <= len) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 10000) $fatal(1, "AXI R timeout at beat %0d", beat_count);

        if (s_axi_rvalid && s_axi_rready) begin
          if (s_axi_rresp !== 2'b00) begin
            $fatal(1, "AXI RRESP error at beat %0d: %0b", beat_count, s_axi_rresp);
          end

          if (s_axi_rlast !== (beat_count == len)) begin
            $fatal(1, "AXI RLAST mismatch at beat %0d, len=%0d", beat_count, len);
          end

          $display("AXI burst read beat %0d/%0d data=0x%08x rlast=%0b",
                   beat_count, len, s_axi_rdata, s_axi_rlast);
          beat_count = beat_count + 1;
        end
      end

      $display("PASS: AXI burst read addr=0x%08x beats=%0d burst=%0b",
               addr, len + 1, burst);
    end
  endtask

  initial begin
    rst_n = 1'b0;

    s_axi_awaddr  = '0;
    s_axi_awlen   = '0;
    s_axi_awsize  = '0;
    s_axi_awburst = '0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata   = '0;
    s_axi_wstrb   = '0;
    s_axi_wlast   = 1'b0;
    s_axi_wvalid  = 1'b0;
    s_axi_bready  = 1'b1;

    s_axi_araddr  = '0;
    s_axi_arlen   = '0;
    s_axi_arsize  = '0;
    s_axi_arburst = '0;
    s_axi_arvalid = 1'b0;
    s_axi_rready  = 1'b1;

    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = '0;
    pwdata  = '0;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (10) @(posedge clk);

    apb_write(32'h0000_0000, 32'h0000_0001);

    // Allow the first-version initialization FSM to complete.
    repeat (200) @(posedge clk);

    // Four-beat, 32-bit AXI INCR burst: ARLEN=3, ARSIZE=2.
    axi_burst_read_check(32'h0000_0000, 8'd3, 3'd2, 2'b01);

    // Four-beat AXI FIXED burst.
    axi_burst_read_check(32'h0000_0040, 8'd3, 3'd2, 2'b00);

    // Four-beat AXI WRAP burst.
    axi_burst_read_check(32'h0000_0038, 8'd3, 3'd2, 2'b10);

    $display("DDR4 controller AXI burst-read regression completed successfully.");
    $finish;
  end

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W),
    .APB_DATA_W(APB_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W),
    .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W),
    .DDR_DQ_W(DDR_DQ_W)
  ) u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awlen   (s_axi_awlen),
    .s_axi_awsize  (s_axi_awsize),
    .s_axi_awburst (s_axi_awburst),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wlast   (s_axi_wlast),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arlen   (s_axi_arlen),
    .s_axi_arsize  (s_axi_arsize),
    .s_axi_arburst (s_axi_arburst),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rlast   (s_axi_rlast),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),
    .paddr         (paddr),
    .psel          (psel),
    .penable       (penable),
    .pwrite        (pwrite),
    .pwdata        (pwdata),
    .prdata        (prdata),
    .pready        (pready),
    .pslverr       (pslverr),
    .ddr_ck_t      (ddr_ck_t),
    .ddr_ck_c      (ddr_ck_c),
    .ddr_reset_n   (ddr_reset_n),
    .ddr_cke       (ddr_cke),
    .ddr_cs_n      (ddr_cs_n),
    .ddr_act_n     (ddr_act_n),
    .ddr_ras_n     (ddr_ras_n),
    .ddr_cas_n     (ddr_cas_n),
    .ddr_we_n      (ddr_we_n),
    .ddr_bg        (ddr_bg),
    .ddr_ba        (ddr_ba),
    .ddr_a         (ddr_a),
    .ddr_odt       (ddr_odt),
    .ddr_par       (ddr_par),
    .ddr_alert_n   (ddr_alert_n),
    .ddr_dq        (ddr_dq),
    .ddr_dqs_t     (ddr_dqs_t),
    .ddr_dqs_c     (ddr_dqs_c),
    .ddr_dm_n      (ddr_dm_n)
  );

  ddr4_sdram_model #(
    .DQ_W(DDR_DQ_W),
    .ADDR_W(DDR_ADDR_W),
    .BA_W(DDR_BA_W),
    .BG_W(DDR_BG_W)
  ) u_ddr4_model (
    .ck_t    (ddr_ck_t),
    .ck_c    (ddr_ck_c),
    .reset_n (ddr_reset_n),
    .cke     (ddr_cke),
    .cs_n    (ddr_cs_n),
    .act_n   (ddr_act_n),
    .ras_n   (ddr_ras_n),
    .cas_n   (ddr_cas_n),
    .we_n    (ddr_we_n),
    .bg      (ddr_bg),
    .ba      (ddr_ba),
    .a       (ddr_a),
    .odt     (ddr_odt),
    .alert_n (ddr_alert_n),
    .dq      (ddr_dq),
    .dqs_t   (ddr_dqs_t),
    .dqs_c   (ddr_dqs_c),
    .dm_n    (ddr_dm_n)
  );

endmodule : tb_ddr4_controller
