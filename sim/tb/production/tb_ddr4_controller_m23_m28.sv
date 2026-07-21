`timescale 1ns/1ps
module tb_ddr4_controller_m23_m28;
  localparam int ID_W=6;
  logic clk=0,rst_n=0; always #1 clk=~clk;
  logic req_valid,req_ready,req_write;logic [ID_W-1:0]req_id;logic[31:0]req_addr;logic[7:0]req_len;logic[2:0]req_size;logic[1:0]req_burst;
  logic cmd_valid,cmd_ready;logic[3:0]cmd_tag;logic cmd_write;logic[ID_W-1:0]cmd_id;logic[31:0]cmd_addr;logic[7:0]cmd_beat;logic cmd_last;
  logic cpl_valid;logic[3:0]cpl_tag;logic[31:0]cpl_rdata;logic[1:0]cpl_resp;
  logic b_valid,b_ready;logic[ID_W-1:0]b_id;logic[1:0]b_resp;
  logic r_valid,r_ready;logic[ID_W-1:0]r_id;logic[31:0]r_data;logic[1:0]r_resp;logic r_last;
  logic refresh_req,refresh_ack,refresh_block;logic[7:0]outstanding_count,command_count;logic protocol_error,refresh_deadline_error;
  ddr4_m23_m28_engine #(.T_REFI(200),.T_RFC(6)) dut(.*);
  task automatic send_req(input logic wr,input logic[5:0]id,input logic[31:0]addr,input logic[7:0]len,input logic[1:0]burst);
    begin @(posedge clk);req_write<=wr;req_id<=id;req_addr<=addr;req_len<=len;req_size<=2;req_burst<=burst;req_valid<=1;while(!req_ready)@(posedge clk);@(posedge clk);req_valid<=0;end
  endtask
  task automatic complete(input logic[3:0]tag,input logic[31:0]data);
    begin @(posedge clk);cpl_tag<=tag;cpl_rdata<=data;cpl_resp<=0;cpl_valid<=1;@(posedge clk);cpl_valid<=0;end
  endtask
  logic[3:0]tags[0:15];logic[31:0]addrs[0:15];logic[5:0]ids[0:15];logic lasts[0:15];integer ncmd;
  always @(posedge clk)if(cmd_valid&&cmd_ready)begin tags[ncmd]=cmd_tag;addrs[ncmd]=cmd_addr;ids[ncmd]=cmd_id;lasts[ncmd]=cmd_last;ncmd=ncmd+1;end
  integer n;logic saw_refresh;
  initial begin
    req_valid=0;req_write=0;req_id=0;req_addr=0;req_len=0;req_size=2;req_burst=1;cmd_ready=1;cpl_valid=0;cpl_tag=0;cpl_rdata=0;cpl_resp=0;b_ready=0;r_ready=0;refresh_ack=0;ncmd=0;saw_refresh=0;
    repeat(5)@(posedge clk);rst_n=1;
    send_req(0,6'h03,32'h0000_1000,0,2'b01);send_req(0,6'h2a,32'h0000_2000,0,2'b01);send_req(0,6'h03,32'h0000_3000,0,2'b01);send_req(1,6'h11,32'h0000_4000,3,2'b01);
    repeat(20)@(posedge clk);if(outstanding_count!=4)$fatal(1,"M23 outstanding mismatch %0d",outstanding_count);$display("PASS M23 outstanding transaction table");
    n=0;while(ncmd<7&&n<150)begin @(posedge clk);n=n+1;end
    if(ncmd<7)$fatal(1,"M26 missing expanded commands %0d",ncmd);
    if(addrs[3]!==32'h4000||addrs[4]!==32'h4004||addrs[5]!==32'h4008||addrs[6]!==32'h400c)$fatal(1,"M26 burst address failure %h %h %h %h",addrs[3],addrs[4],addrs[5],addrs[6]);
    if(!lasts[6])$fatal(1,"M26 last beat missing");$display("PASS M26 complete burst beat expansion");
    if(command_count!=0)$fatal(1,"M27 command queue did not drain %0d",command_count);$display("PASS M27 multi-entry bank command scheduler");
    complete(tags[1],32'haaaa_002a);complete(tags[0],32'h1111_0003);complete(tags[2],32'h2222_0003);complete(tags[3],0);complete(tags[4],0);complete(tags[5],0);complete(tags[6],0);
    r_ready=1;b_ready=0;
    n=0;while(!(r_valid&&r_id==6'h2a)&&n<100)begin @(posedge clk);n=n+1;end if(n>=100||r_data!==32'haaaa_002a)$fatal(1,"M24 cross-ID completion failed");@(posedge clk);
    n=0;while(!(r_valid&&r_id==6'h03&&r_data==32'h1111_0003)&&n<100)begin @(posedge clk);n=n+1;end if(n>=100)$fatal(1,"M24 first same-ID response missing");@(posedge clk);
    n=0;while(!(r_valid&&r_id==6'h03&&r_data==32'h2222_0003)&&n<100)begin @(posedge clk);n=n+1;end if(n>=100)$fatal(1,"M24 per-ID ordering failed");$display("PASS M24 read reorder buffer");
    b_ready=1;n=0;while(!(b_valid&&b_id==6'h11)&&n<100)begin @(posedge clk);n=n+1;end if(n>=100)$fatal(1,"M25 independent B queue failed");$display("PASS M25 independent B and R response queues");
    n=0;while(!refresh_req&&n<300)begin @(posedge clk);n=n+1;end if(n>=300||!refresh_block)$fatal(1,"M28 refresh request/block missing");
    saw_refresh=1;@(posedge clk);refresh_ack<=1;@(posedge clk);refresh_ack<=0;repeat(3)begin @(posedge clk);if(!refresh_block)$fatal(1,"M28 tRFC block released early");end
    n=0;while(refresh_block&&n<20)begin @(posedge clk);n=n+1;end if(n>=20)$fatal(1,"M28 tRFC block stuck");if(refresh_deadline_error)$fatal(1,"M28 unexpected refresh deadline error");
    $display("PASS M28 production refresh deadline and tRFC control");if(protocol_error)$fatal(1,"protocol_error asserted");$display("PASS M23-M28 transaction architecture closure");$finish;
  end
  initial begin #200000;$fatal(1,"M23-M28 global timeout");end
endmodule
