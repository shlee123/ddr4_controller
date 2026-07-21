`timescale 1ns/1ps
module tb_ddr4_controller_m32;
  localparam ADDR_W=32; localparam DATA_W=32; localparam WB_DEPTH=32; localparam VC_LINES=16;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg wr_valid; wire wr_ready; reg[ADDR_W-1:0]wr_addr;reg[DATA_W-1:0]wr_data;reg[DATA_W/8-1:0]wr_strb;
  wire mem_wr_valid;reg mem_wr_ready;wire[ADDR_W-1:0]mem_wr_addr;wire[DATA_W-1:0]mem_wr_data;wire[DATA_W/8-1:0]mem_wr_strb;
  reg victim_lookup_valid;reg[ADDR_W-1:0]victim_lookup_addr;wire victim_lookup_hit;wire[DATA_W-1:0]victim_lookup_data;
  reg victim_insert_valid;reg[ADDR_W-1:0]victim_insert_addr;reg[DATA_W-1:0]victim_insert_data;reg victim_insert_dirty;
  wire victim_evict_valid;reg victim_evict_ready;wire[ADDR_W-1:0]victim_evict_addr;wire[DATA_W-1:0]victim_evict_data;
  wire[$clog2(WB_DEPTH):0]write_buffer_count;reg invalidate;integer errors;integer i;
  ddr4_m32_cache_subsystem #(.WRITE_BUFFER_DEPTH(WB_DEPTH),.VICTIM_CACHE_LINES(VC_LINES)) dut(.*);
  task push_write;input[31:0]a;input[31:0]d;input[3:0]s;begin
    @(negedge clk);wr_valid=1;wr_addr=a;wr_data=d;wr_strb=s;
    while(!wr_ready)@(negedge clk);@(negedge clk);wr_valid=0;
  end endtask
  task insert_victim;input[31:0]a;input[31:0]d;input dirty;begin
    @(negedge clk);victim_insert_valid=1;victim_insert_addr=a;victim_insert_data=d;victim_insert_dirty=dirty;
    while(victim_evict_valid&&!victim_evict_ready)@(negedge clk);@(negedge clk);victim_insert_valid=0;
  end endtask
  task lookup_victim;input[31:0]a;input[31:0]expected_data;begin
    @(negedge clk);victim_lookup_valid=1;victim_lookup_addr=a;#1;
    if(!victim_lookup_hit||victim_lookup_data!==expected_data)begin $display("ERROR victim lookup a=%h data=%h",a,victim_lookup_data);errors=errors+1;end
    @(negedge clk);victim_lookup_valid=0;
  end endtask
  initial begin
    wr_valid=0;wr_addr=0;wr_data=0;wr_strb=0;mem_wr_ready=0;victim_lookup_valid=0;victim_lookup_addr=0;
    victim_insert_valid=0;victim_insert_addr=0;victim_insert_data=0;victim_insert_dirty=0;victim_evict_ready=1;invalidate=0;errors=0;
    repeat(4)@(negedge clk);rst_n=1;
    push_write(32'h1000,32'h11223344,4'b1111);
    push_write(32'h1000,32'haa00cc00,4'b1010);
    if(write_buffer_count!==1)begin $display("ERROR merge count=%0d",write_buffer_count);errors=errors+1;end
    #1;if(mem_wr_data!==32'haa22cc44||mem_wr_strb!==4'hf)begin $display("ERROR merge data=%h strb=%h",mem_wr_data,mem_wr_strb);errors=errors+1;end
    mem_wr_ready=1;@(negedge clk);mem_wr_ready=0;@(negedge clk);
    if(write_buffer_count!==0)begin $display("ERROR drain count=%0d",write_buffer_count);errors=errors+1;end
    for(i=0;i<WB_DEPTH;i=i+1)push_write(32'h2000+i*4,32'h50000000+i,4'hf);
    if(write_buffer_count!==WB_DEPTH)begin $display("ERROR default WB depth count=%0d",write_buffer_count);errors=errors+1;end
    mem_wr_ready=1;repeat(WB_DEPTH+1)@(negedge clk);mem_wr_ready=0;
    for(i=0;i<VC_LINES;i=i+1)insert_victim(32'h4000+i*4,32'h60000000+i,1'b0);
    lookup_victim(32'h4000,32'h60000000);
    insert_victim(32'h8000,32'hdeadbeef,1'b1);
    for(i=1;i<VC_LINES;i=i+1)insert_victim(32'h8000+i*4,32'h70000000+i,1'b0);
    @(negedge clk);victim_evict_ready=0;victim_insert_valid=1;victim_insert_addr=32'hc000;victim_insert_data=32'h12345678;victim_insert_dirty=0;#1;
    if(!victim_evict_valid||victim_evict_addr!==32'h8000||victim_evict_data!==32'hdeadbeef)begin $display("ERROR dirty eviction");errors=errors+1;end
    @(negedge clk);victim_evict_ready=1;@(negedge clk);victim_insert_valid=0;
    if(errors==0)$display("PASS M30-M32 write_buffer=%0d victim_lines=%0d",WB_DEPTH,VC_LINES);
    else $display("FAIL M30-M32 errors=%0d",errors);
    #20;$finish;
  end
endmodule
