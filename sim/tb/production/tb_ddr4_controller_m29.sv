// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module tb_ddr4_controller_m29;
  localparam ADDR_W=32, DATA_W=32, ID_W=6, TAG_W=4;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;

  reg [ID_W-1:0] awid; reg [ADDR_W-1:0] awaddr; reg [7:0] awlen;
  reg [2:0] awsize; reg [1:0] awburst; reg awvalid; wire awready;
  reg [DATA_W-1:0] wdata; reg [DATA_W/8-1:0] wstrb; reg wlast,wvalid; wire wready;
  wire [ID_W-1:0] bid; wire [1:0] bresp; wire bvalid; reg bready=1;
  reg [ID_W-1:0] arid; reg [ADDR_W-1:0] araddr; reg [7:0] arlen;
  reg [2:0] arsize; reg [1:0] arburst; reg arvalid; wire arready;
  wire [ID_W-1:0] rid; wire [DATA_W-1:0] rdata; wire [1:0] rresp;
  wire rlast,rvalid; reg rready=1;

  wire cmd_valid; reg cmd_ready=1; wire [TAG_W-1:0] cmd_tag; wire cmd_write;
  wire [ID_W-1:0] cmd_id; wire [ADDR_W-1:0] cmd_addr; wire [7:0] cmd_beat; wire cmd_last;
  reg cpl_valid; reg [TAG_W-1:0] cpl_tag; reg [DATA_W-1:0] cpl_rdata; reg [1:0] cpl_resp;
  wire refresh_req; reg refresh_ack; wire refresh_block;
  wire [7:0] outstanding_count,command_count;
  wire protocol_error,refresh_deadline_error,axi_write_protocol_error;

  integer errors=0;
  integer read_count=0;
  integer write_cmd_count=0;
  integer max_outstanding=0;
  integer id3_count=0;
  reg refresh_seen=0;
  reg pending_cpl;
  reg [TAG_W-1:0] pending_tag;
  reg [DATA_W-1:0] pending_data;
  reg [1:0] pending_resp;

  ddr4_m29_axi_transaction_engine #(
    .ADDR_W(ADDR_W),.DATA_W(DATA_W),.ID_W(ID_W),.TAG_W(TAG_W),
    .T_REFI(80),.T_RFC(5)
  ) dut (
    .clk(clk),.rst_n(rst_n),
    .s_axi_awid(awid),.s_axi_awaddr(awaddr),.s_axi_awlen(awlen),
    .s_axi_awsize(awsize),.s_axi_awburst(awburst),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bid(bid),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_arid(arid),.s_axi_araddr(araddr),.s_axi_arlen(arlen),
    .s_axi_arsize(arsize),.s_axi_arburst(arburst),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
    .s_axi_rid(rid),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .native_cmd_valid(cmd_valid),.native_cmd_ready(cmd_ready),.native_cmd_tag(cmd_tag),
    .native_cmd_write(cmd_write),.native_cmd_id(cmd_id),.native_cmd_addr(cmd_addr),
    .native_cmd_beat(cmd_beat),.native_cmd_last(cmd_last),
    .native_cpl_valid(cpl_valid),.native_cpl_tag(cpl_tag),.native_cpl_rdata(cpl_rdata),.native_cpl_resp(cpl_resp),
    .refresh_req(refresh_req),.refresh_ack(refresh_ack),.refresh_block(refresh_block),
    .outstanding_count(outstanding_count),.command_count(command_count),
    .protocol_error(protocol_error),.refresh_deadline_error(refresh_deadline_error),
    .axi_write_protocol_error(axi_write_protocol_error)
  );

  task send_read;
    input [ID_W-1:0] id;
    input [ADDR_W-1:0] addr;
    begin
      @(negedge clk); arid=id; araddr=addr; arlen=0; arsize=2; arburst=1; arvalid=1;
      while (!arready) @(negedge clk);
      @(negedge clk); arvalid=0;
    end
  endtask

  task send_aw;
    input [ID_W-1:0] id;
    input [ADDR_W-1:0] addr;
    input [7:0] len;
    begin
      @(negedge clk); awid=id; awaddr=addr; awlen=len; awsize=2; awburst=1; awvalid=1;
      while (!awready) @(negedge clk);
      @(negedge clk); awvalid=0;
    end
  endtask

  task send_w;
    input [DATA_W-1:0] data;
    input last;
    begin
      @(negedge clk); wdata=data; wstrb={DATA_W/8{1'b1}}; wlast=last; wvalid=1;
      while (!wready) @(negedge clk);
      @(negedge clk); wvalid=0; wlast=0;
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      cpl_valid <= 0; pending_cpl <= 0; refresh_ack <= 0;
    end else begin
      cpl_valid <= pending_cpl;
      cpl_tag <= pending_tag;
      cpl_rdata <= pending_data;
      cpl_resp <= pending_resp;
      pending_cpl <= 0;
      refresh_ack <= refresh_req;
      if (refresh_req) refresh_seen <= 1;
      if (cmd_valid && cmd_ready) begin
        pending_cpl <= 1;
        pending_tag <= cmd_tag;
        pending_data <= cmd_addr ^ {26'd0,cmd_id};
        pending_resp <= 0;
        if (cmd_write) write_cmd_count <= write_cmd_count+1;
      end
      if (outstanding_count > max_outstanding) max_outstanding <= outstanding_count;
    end
  end

  always @(posedge clk) begin
    if (rst_n && rvalid && rready) begin
      read_count <= read_count+1;
      if (!rlast || rresp != 0) begin
        $display("ERROR invalid read response flags"); errors <= errors+1;
      end
      if (rid == 6'd3) begin
        if (id3_count == 0 && rdata !== (32'h00001000 ^ 32'd3)) begin
          $display("ERROR first ID3 response out of order data=%h",rdata); errors <= errors+1;
        end
        if (id3_count == 1 && rdata !== (32'h00003000 ^ 32'd3)) begin
          $display("ERROR second ID3 response out of order data=%h",rdata); errors <= errors+1;
        end
        id3_count <= id3_count+1;
      end else if (rid == 6'd5) begin
        if (rdata !== (32'h00002000 ^ 32'd5)) begin
          $display("ERROR ID5 response data=%h",rdata); errors <= errors+1;
        end
      end else begin
        $display("ERROR unexpected RID %0d",rid); errors <= errors+1;
      end
    end
  end

  initial begin
    awid=0;awaddr=0;awlen=0;awsize=2;awburst=1;awvalid=0;
    wdata=0;wstrb=0;wlast=0;wvalid=0;
    arid=0;araddr=0;arlen=0;arsize=2;arburst=1;arvalid=0;
    cpl_valid=0;cpl_tag=0;cpl_rdata=0;cpl_resp=0;refresh_ack=0;
    pending_cpl=0;pending_tag=0;pending_data=0;pending_resp=0;
    repeat(5) @(posedge clk); rst_n=1;

    fork
      send_read(6'd3,32'h00001000);
      begin repeat(1) @(posedge clk); send_read(6'd5,32'h00002000); end
      begin repeat(2) @(posedge clk); send_read(6'd3,32'h00003000); end
    join

    send_aw(6'd9,32'h00004000,8'd1);
    send_w(32'h11112222,1'b0);
    send_w(32'h33334444,1'b1);

    repeat(300) @(posedge clk);

    if (read_count != 3) begin $display("ERROR read_count=%0d",read_count); errors=errors+1; end
    if (id3_count != 2) begin $display("ERROR id3_count=%0d",id3_count); errors=errors+1; end
    if (write_cmd_count != 2) begin $display("ERROR write_cmd_count=%0d",write_cmd_count); errors=errors+1; end
    if (!bvalid && dut.u_transaction_engine.b_count != 0) begin $display("ERROR write response not retired"); errors=errors+1; end
    if (max_outstanding < 2) begin $display("ERROR outstanding concurrency not demonstrated max=%0d",max_outstanding); errors=errors+1; end
    if (!refresh_seen) begin $display("ERROR refresh path not exercised"); errors=errors+1; end
    if (protocol_error || refresh_deadline_error || axi_write_protocol_error) begin
      $display("ERROR status protocol=%b refresh=%b axi_write=%b",protocol_error,refresh_deadline_error,axi_write_protocol_error);
      errors=errors+1;
    end
    if (errors==0) begin
      $display("PASS M29 AXI front-end integrated with M23-M28 transaction engine");
      $display("PASS M29 multiple outstanding AXI IDs and ordered responses");
      $display("PASS M29 AW/W assembly, native commands, completion and refresh paths");
    end else begin
      $display("FAIL M29 errors=%0d",errors);
      $fatal(1);
    end
    $finish;
  end
endmodule
