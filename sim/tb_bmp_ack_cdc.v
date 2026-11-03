`timescale 1ns/1ps
// Removing either ACK synchronizer stage must release write_req too early here.
// The actual BMP parser/decoder is exercised through its public byte interface.
module tb_bmp_ack_cdc;
 reg clk=0,mem_clk=0;
 always #5 clk=~clk;        // SD-side destination: 100 MHz
 always #4 mem_clk=~mem_clk; // memory-side source: 125 MHz
 reg rst=1,load_start=0,ack=0,valid=0,sec_end=0;
 reg [7:0] data=0;
 wire ready,write_req,read_req,pixel_valid;
 wire [31:0] read_addr;
 wire [23:0] pixel;
 reg [7:0] bytes[0:63];
 integer pixels=0,cases=0,phase,delay_cycles,i;
 reg [4:0] phase_seen=0;

 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),
  .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(7'd0),
  .load_start(load_start),.load_sector(32'd123),.sd_init_done(1'b1),
  .bmp_width(16'd2),.bmp_height(16'd1),.write_req(write_req),.write_req_ack(ack),
  .sd_sec_read(read_req),.sd_sec_read_addr(read_addr),.sd_sec_read_data(data),
  .sd_sec_read_data_valid(valid),.sd_sec_read_end(sec_end),
  .bmp_data_wr_en(pixel_valid),.bmp_data(pixel));

 always @(posedge clk) begin
  #1;
  if(rst) pixels=0;
  else if(pixel_valid) begin
   if(pixels==0 && pixel!==24'h332211)$fatal(1,"first decoded pixel changed: %h",pixel);
   if(pixels==1 && pixel!==24'h665544)$fatal(1,"second decoded pixel changed: %h",pixel);
   if(pixels>1)$fatal(1,"duplicate pixel after ACK");
   pixels=pixels+1;
  end
 end

 task reset_reader;
  begin
   @(negedge clk);rst=1;load_start=0;ack=0;valid=0;sec_end=0;
   repeat(4)@(negedge clk);
   rst=0;
  end
 endtask

 task send_bytes;
  input integer count;
  integer b;
  begin
   for(b=0;b<count;b=b+1) begin
    @(negedge clk);valid=1;data=bytes[b];
   end
   @(negedge clk);valid=0;sec_end=1;
   @(negedge clk);sec_end=0;
  end
 endtask

 task start_load;
  begin
   @(negedge clk);load_start=1;
   @(negedge clk);load_start=0;
   wait(read_req);
   if(read_addr!==123)$fatal(1,"header sector address changed");
   send_bytes(54);
   wait(write_req);
   repeat(3)begin
    @(posedge clk);#1;
    if(!write_req || read_req || pixel_valid)$fatal(1,"request did not wait for ACK");
   end
  end
 endtask

 task finish_load;
  begin
   wait(read_req);
   if(read_addr!==123)$fatal(1,"pixel sector address changed");
   send_bytes(64);
   wait(ready);
   @(negedge clk);
   if(!ready || write_req || pixels!=2)$fatal(1,"BMP completion changed: ready=%b req=%b pixels=%0d",ready,write_req,pixels);
  end
 endtask

 task test_ack;
  input integer source_edges,wait_cycles,pulsed;
  begin
   reset_reader;
   start_load;
   repeat(wait_cycles)begin
    @(posedge clk);#1;
    if(!write_req || read_req)$fatal(1,"request escaped while ACK was delayed");
   end
   // Select each of the five 125:100 MHz phase classes explicitly.
   @(posedge mem_clk);
   while(($time%10)!=(source_edges-1)*2)@(posedge mem_clk);
   #0.25;ack=1;
   phase_seen[($time%10)/2]=1'b1;
   #0.10;
   if(!write_req || read_req)$fatal(1,"combinational ACK bypass");
   @(posedge clk);#1;
   if(!write_req || read_req)$fatal(1,"raw ACK bypassed synchronization phase=%0d",source_edges);
   if(pulsed)begin @(negedge clk);ack=0;end
   @(posedge clk);#1;
   if(!write_req || read_req)$fatal(1,"ACK first stage bypassed phase=%0d",source_edges);
   @(posedge clk);#1;
   if(write_req || read_req)$fatal(1,"synchronized ACK was not consumed once phase=%0d",source_edges);
   if(!pulsed)begin @(posedge mem_clk);#0.25;ack=0;end
   finish_load;
   cases=cases+1;
  end
 endtask

 initial begin
  for(i=0;i<64;i=i+1)bytes[i]=0;
  bytes[0]="B";bytes[1]="M";bytes[2]=64;bytes[10]=54;
  bytes[14]=40;bytes[18]=2;bytes[22]=1;bytes[26]=1;bytes[28]=24;
  bytes[54]=8'h11;bytes[55]=8'h22;bytes[56]=8'h33;
  bytes[57]=8'h44;bytes[58]=8'h55;bytes[59]=8'h66;
  for(phase=1;phase<=5;phase=phase+1)
   for(delay_cycles=0;delay_cycles<=7;delay_cycles=delay_cycles+7)
    test_ack(phase,delay_cycles,0);
  test_ack(3,2,1); // a one-destination-sample pulse still propagates exactly once
  if(phase_seen!==5'b11111)$fatal(1,"not all five source/destination phases exercised: %b",phase_seen);
  // Reset after the first ACK sample must erase the pending acknowledgement.
  reset_reader;start_load;
  @(negedge clk);ack=1;
  @(posedge clk);#1;
  if(!write_req)$fatal(1,"raw ACK bypass before reset");
  reset_reader;start_load;
  repeat(5)begin @(posedge clk);#1;if(!write_req || read_req)$fatal(1,"stale ACK survived reset");end
  $display("PASS: ACK CDC %0d phase/delay/pulse loads, exact BMP pixels and pending-ACK reset",cases);
  $finish;
 end
 initial begin #1000000;$fatal(1,"ACK CDC timeout");end
endmodule
