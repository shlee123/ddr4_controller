`timescale 1ns/1ps

module tb_ddr4_controller_m5;
  import ddr4_ctrl_pkg::*;

  localparam int AXI_ADDR_W = 32;
  localparam int AXI_DATA_W = 32;
  localparam int APB_ADDR_W = 32;
  localparam int APB_DATA_W = 32;
  localparam int DDR_ADDR_W = 17;
  localparam int DDR_BG_W   = 2;
  localparam int DDR_BA_W   = 2;
  localparam int DDR_DQ_W   = 16;
  localparam int DDR_DM_W   = 2;
  localparam logic [31:0] REG_STATUS = 32'h0000_0004;
  localparam int TIMEOUT = 200000;
  localparam int WORDS = 64;
  localparam int RANDOM_TRANSACTIONS = 1000;
  localparam int QUEUE_BURST = 8;

  logic axi_clk = 1'b0;
  logic axi_rst_n = 1'b0;
  logic ddr_clk = 1'b0;
  logic ddr_rst_n = 1'b0;
  always #2.5 axi_clk = ~axi_clk;
  always #1.0 ddr_clk = ~ddr_clk;

  logic [31:0] s_axi_awaddr;
  logic [7:0]  s_axi_awlen;
  logic [2:0]  s_axi_awsize;
  logic [1:0]  s_axi_awburst;
  logic        s_axi_awvalid;
  logic        s_axi_awready;
  logic [31:0] s_axi_wdata;
  logic [3:0]  s_axi_wstrb;
  logic        s_axi_wlast;
  logic        s_axi_wvalid;
  logic        s_axi_wready;
  logic [1:0]  s_axi_bresp;
  logic        s_axi_bvalid;
  logic        s_axi_bready;
  logic [31:0] s_axi_araddr;
  logic [7:0]  s_axi_arlen;
  logic [2:0]  s_axi_arsize;
  logic [1:0]  s_axi_arburst;
  logic        s_axi_arvalid;
  logic        s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0]  s_axi_rresp;
  logic        s_axi_rlast;
  logic        s_axi_rvalid;
  logic        s_axi_rready;

  logic [31:0] paddr, pwdata, prdata;
  logic psel, penable, pwrite, pready, pslverr;
  logic ddr_ck_t, ddr_ck_c, ddr_reset_n, ddr_cke, ddr_cs_n;
  logic ddr_act_n, ddr_ras_n, ddr_cas_n, ddr_we_n;
  logic [1:0] ddr_bg, ddr_ba;
  logic [16:0] ddr_a;
  logic ddr_odt, ddr_par, ddr_alert_n;
  wire [15:0] ddr_dq;
  wire [1:0] ddr_dqs_t, ddr_dqs_c, ddr_dm_n;

  ddr4_controller_top #(
    .AXI_ADDR_W(AXI_ADDR_W), .AXI_DATA_W(AXI_DATA_W),
    .APB_ADDR_W(APB_ADDR_W), .APB_DATA_W(APB_DATA_W),
    .DDR_ADDR_W(DDR_ADDR_W), .DDR_BG_W(DDR_BG_W),
    .DDR_BA_W(DDR_BA_W), .DDR_DQ_W(DDR_DQ_W), .DDR_DM_W(DDR_DM_W)
  ) dut (
    .axi_clk, .axi_rst_n, .clk(ddr_clk), .rst_n(ddr_rst_n),
    .s_axi_awaddr, .s_axi_awlen, .s_axi_awsize, .s_axi_awburst, .s_axi_awvalid, .s_axi_awready,
    .s_axi_wdata, .s_axi_wstrb, .s_axi_wlast, .s_axi_wvalid, .s_axi_wready,
    .s_axi_bresp, .s_axi_bvalid, .s_axi_bready,
    .s_axi_araddr, .s_axi_arlen, .s_axi_arsize, .s_axi_arburst, .s_axi_arvalid, .s_axi_arready,
    .s_axi_rdata, .s_axi_rresp, .s_axi_rlast, .s_axi_rvalid, .s_axi_rready,
    .paddr, .psel, .penable, .pwrite, .pwdata, .prdata, .pready, .pslverr,
    .ddr_ck_t, .ddr_ck_c, .ddr_reset_n, .ddr_cke, .ddr_cs_n, .ddr_act_n,
    .ddr_ras_n, .ddr_cas_n, .ddr_we_n, .ddr_bg, .ddr_ba, .ddr_a,
    .ddr_odt, .ddr_par, .ddr_alert_n, .ddr_dq, .ddr_dqs_t, .ddr_dqs_c, .ddr_dm_n
  );

  ddr4_sdram_model #(.DQ_W(16), .ADDR_W(17), .BA_W(2), .BG_W(2)) dram (
    .reset_n(ddr_reset_n), .ck_t(ddr_ck_t), .ck_c(ddr_ck_c), .cke(ddr_cke), .cs_n(ddr_cs_n),
    .act_n(ddr_act_n), .ras_n(ddr_ras_n), .cas_n(ddr_cas_n), .we_n(ddr_we_n),
    .a(ddr_a), .ba(ddr_ba), .bg(ddr_bg), .odt(ddr_odt), .dq(ddr_dq),
    .dqs_t(ddr_dqs_t), .dqs_c(ddr_dqs_c), .dm_n(ddr_dm_n), .alert_n(ddr_alert_n)
  );

  logic random_ready_enable;
  logic [31:0] ready_lfsr;
  always_ff @(posedge axi_clk or negedge axi_rst_n) begin
    if (!axi_rst_n) begin
      ready_lfsr <= 32'h1ace_b00c;
      s_axi_bready <= 1'b0;
      s_axi_rready <= 1'b0;
    end else if (random_ready_enable) begin
      ready_lfsr <= {ready_lfsr[30:0], ready_lfsr[31] ^ ready_lfsr[21] ^ ready_lfsr[1] ^ ready_lfsr[0]};
      s_axi_bready <= ready_lfsr[0] | ready_lfsr[3] | ready_lfsr[7];
      s_axi_rready <= ready_lfsr[1] | ready_lfsr[4] | ready_lfsr[8];
    end
  end

  logic [1:0] stalled_bresp;
  logic [31:0] stalled_rdata;
  logic [1:0] stalled_rresp;
  logic stalled_rlast;
  logic b_stalled, r_stalled;
  always_ff @(posedge axi_clk or negedge axi_rst_n) begin
    if (!axi_rst_n) begin
      b_stalled <= 1'b0;
      r_stalled <= 1'b0;
    end else begin
      if (s_axi_bvalid && !s_axi_bready) begin
        if (!b_stalled) stalled_bresp <= s_axi_bresp;
        else if (!s_axi_bvalid || s_axi_bresp !== stalled_bresp)
          $fatal(1, "B channel changed while stalled");
        b_stalled <= 1'b1;
      end else begin
        b_stalled <= 1'b0;
      end

      if (s_axi_rvalid && !s_axi_rready) begin
        if (!r_stalled) begin
          stalled_rdata <= s_axi_rdata;
          stalled_rresp <= s_axi_rresp;
          stalled_rlast <= s_axi_rlast;
        end else if (!s_axi_rvalid || s_axi_rdata !== stalled_rdata ||
                     s_axi_rresp !== stalled_rresp || s_axi_rlast !== stalled_rlast) begin
          $fatal(1, "R channel changed while stalled");
        end
        r_stalled <= 1'b1;
      end else begin
        r_stalled <= 1'b0;
      end
    end
  end

  function automatic logic [31:0] word_addr(input int index);
    word_addr = 32'h0000_1000 + (index << 2);
  endfunction

  task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
    integer n;
    begin
      @(posedge axi_clk);
      paddr <= addr; pwrite <= 1'b0; psel <= 1'b1; penable <= 1'b0;
      @(posedge axi_clk);
      penable <= 1'b1;
      n = 0;
      while (!pready && n < TIMEOUT) begin @(posedge axi_clk); n = n + 1; end
      if (!pready) $fatal(1, "APB timeout");
      data = prdata;
      @(posedge axi_clk);
      psel <= 1'b0; penable <= 1'b0; paddr <= '0;
    end
  endtask

  task automatic send_aw(input logic [31:0] addr);
    integer n;
    begin
      @(posedge axi_clk);
      s_axi_awaddr <= addr;
      s_axi_awlen <= 8'd0;
      s_axi_awsize <= 3'd2;
      s_axi_awburst <= 2'b01;
      s_axi_awvalid <= 1'b1;
      n = 0;
      while (!s_axi_awready && n < TIMEOUT) begin @(posedge axi_clk); n = n + 1; end
      if (!s_axi_awready) $fatal(1, "AW timeout addr=%h", addr);
      @(posedge axi_clk);
      s_axi_awvalid <= 1'b0;
    end
  endtask

  task automatic send_w(input logic [31:0] data);
    integer n;
    begin
      s_axi_wdata <= data;
      s_axi_wstrb <= 4'hf;
      s_axi_wlast <= 1'b1;
      s_axi_wvalid <= 1'b1;
      n = 0;
      while (!s_axi_wready && n < TIMEOUT) begin @(posedge axi_clk); n = n + 1; end
      if (!s_axi_wready) $fatal(1, "W timeout");
      @(posedge axi_clk);
      s_axi_wvalid <= 1'b0;
      s_axi_wlast <= 1'b0;
    end
  endtask

  task automatic wait_b;
    integer n;
    begin
      n = 0;
      while (!(s_axi_bvalid && s_axi_bready) && n < TIMEOUT) begin @(posedge axi_clk); n = n + 1; end
      if (!(s_axi_bvalid && s_axi_bready)) $fatal(1, "B timeout");
      if (s_axi_bresp !== 2'b00) $fatal(1, "BRESP error %b", s_axi_bresp);
    end
  endtask

  task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      send_aw(addr);
      send_w(data);
      wait_b();
    end
  endtask

  task automatic send_ar(input logic [31:0] addr);
    integer n;
    begin
      @(posedge axi_clk);
      s_axi_araddr <= addr;
      s_axi_arlen <= 8'd0;
      s_axi_arsize <= 3'd2;
      s_axi_arburst <= 2'b01;
      s_axi_arvalid <= 1'b1;
      n = 0;
      while (!s_axi_arready && n < TIMEOUT) begin @(posedge axi_clk); n = n + 1; end
      if (!s_axi_arready) $fatal(1, "AR timeout addr=%h", addr);
      @(posedge axi_clk);
      s_axi_arvalid <= 1'b0;
    end
  endtask

  task automatic wait_r(output logic [31:0] data);
    integer n;
    begin
      n = 0;
      while (!(s_axi_rvalid && s_axi_rready) && n < TIMEOUT) begin @(posedge axi_clk); n = n + 1; end
      if (!(s_axi_rvalid && s_axi_rready)) $fatal(1, "R timeout");
      if (s_axi_rresp !== 2'b00) $fatal(1, "RRESP error %b", s_axi_rresp);
      if (!s_axi_rlast) $fatal(1, "Missing RLAST");
      data = s_axi_rdata;
    end
  endtask

  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      send_ar(addr);
      wait_r(data);
    end
  endtask

  logic [31:0] scoreboard [0:WORDS-1];
  logic [31:0] status, rd, data;
  integer i, n, index;
  integer writes, reads, transactions;

  initial begin
    s_axi_awaddr = '0; s_axi_awlen = 0; s_axi_awsize = 2; s_axi_awburst = 1; s_axi_awvalid = 0;
    s_axi_wdata = '0; s_axi_wstrb = 0; s_axi_wlast = 0; s_axi_wvalid = 0;
    s_axi_araddr = '0; s_axi_arlen = 0; s_axi_arsize = 2; s_axi_arburst = 1; s_axi_arvalid = 0;
    paddr = '0; psel = 0; penable = 0; pwrite = 0; pwdata = '0;
    random_ready_enable = 1'b0;
    writes = 0; reads = 0; transactions = 0;

    repeat (8) @(posedge axi_clk);
    axi_rst_n = 1'b1;
    repeat (8) @(posedge ddr_clk);
    ddr_rst_n = 1'b1;

    status = 0; n = 0;
    while (!status[0] && n < TIMEOUT) begin apb_read(REG_STATUS, status); n = n + 1; end
    if (!status[0]) $fatal(1, "init_done timeout");

    // Fill the scoreboard so every subsequent random read is defined.
    random_ready_enable = 1'b1;
    for (i = 0; i < WORDS; i = i + 1) begin
      data = 32'h5a00_0000 ^ i;
      axi_write(word_addr(i), data);
      scoreboard[i] = data;
      writes = writes + 1;
      transactions = transactions + 1;
    end

    // Queue-boundary write stress: hold BREADY low while eight writes are accepted.
    random_ready_enable = 1'b0;
    @(posedge axi_clk); s_axi_bready <= 1'b0; s_axi_rready <= 1'b0;
    for (i = 0; i < QUEUE_BURST; i = i + 1) begin
      data = 32'ha500_1000 + i;
      send_aw(word_addr(i));
      send_w(data);
      scoreboard[i] = data;
      writes = writes + 1;
      transactions = transactions + 1;
    end
    repeat (20) @(posedge axi_clk);
    s_axi_bready <= 1'b1;
    for (i = 0; i < QUEUE_BURST; i = i + 1) wait_b();

    // Queue-boundary read stress: hold RREADY low while eight reads are accepted.
    s_axi_rready <= 1'b0;
    for (i = 0; i < QUEUE_BURST; i = i + 1) send_ar(word_addr(i));
    repeat (20) @(posedge axi_clk);
    s_axi_rready <= 1'b1;
    for (i = 0; i < QUEUE_BURST; i = i + 1) begin
      wait_r(rd);
      if (rd !== scoreboard[i])
        $fatal(1, "Queued read mismatch index=%0d expected=%h actual=%h", i, scoreboard[i], rd);
      reads = reads + 1;
      transactions = transactions + 1;
    end

    random_ready_enable = 1'b1;
    for (i = 0; i < RANDOM_TRANSACTIONS; i = i + 1) begin
      index = $urandom_range(0, WORDS-1);
      if ($urandom_range(0, 1)) begin
        data = $urandom;
        axi_write(word_addr(index), data);
        scoreboard[index] = data;
        writes = writes + 1;
      end else begin
        axi_read(word_addr(index), rd);
        if (rd !== scoreboard[index])
          $fatal(1, "Random read mismatch txn=%0d index=%0d expected=%h actual=%h", i, index, scoreboard[index], rd);
        reads = reads + 1;
      end
      transactions = transactions + 1;
    end

    $display("PASS M5 AXI backpressure randomized regression: transactions=%0d writes=%0d reads=%0d", transactions, writes, reads);
    $finish;
  end

  initial begin
    #20000000;
    $fatal(1, "M5 global timeout");
  end
endmodule
