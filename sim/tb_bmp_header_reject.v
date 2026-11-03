`timescale 1ns/1ps
// Malformed files must never reserve a frame buffer or emit any partial image.
module tb_bmp_header_reject;
 reg clk=0,rst=1,start=0,valid=0,sec_end=0;
 always #5 clk=~clk;
 reg [7:0] data=0,bytes[0:511];
 wire ready,wr,read_req,pv;
 integer i,n,cases=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(1'b0),.scan_start_sector(32'd0),
  .scan_max_sector(32'd0),.scan_target_count(7'd0),.load_start(start),.load_sector(32'd123),
  .sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),.write_req(wr),.write_req_ack(1'b0),
  .sd_sec_read(read_req),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),
  .sd_sec_read_end(sec_end),.bmp_data_wr_en(pv));
 always @(posedge clk)if(!rst && (wr || pv))$fatal(1,"invalid BMP reached writer case=%0d",n);
 task word;input integer off;input [31:0] v;
  begin bytes[off]=v[7:0];bytes[off+1]=v[15:8];bytes[off+2]=v[23:16];bytes[off+3]=v[31:24];end
 endtask
 initial begin
  for(n=0;n<12;n=n+1)begin
   @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
   for(i=0;i<512;i=i+1)bytes[i]=0;
   bytes[0]="B";bytes[1]="M";word(2,921654);word(10,54);word(14,40);word(18,640);word(22,480);
   bytes[26]=1;bytes[28]=24;
   case(n)
    0:bytes[0]="Q";
    1:word(14,0);
    2:bytes[26]=2;
    3:bytes[28]=32;
    4:word(30,1);
    5:word(18,0);
    6:word(18,1025);
    7:word(22,0);
    8:word(22,-1025);
    9:word(10,53);
    10:word(10,65536);
    11:word(2,921653); // exactly one byte shorter than padded pixel extent
   endcase
   @(negedge clk);start=1;
   @(negedge clk);start=0;
   wait(read_req);
   for(i=0;i<512;i=i+1)begin @(negedge clk);valid=1;data=bytes[i];end
   @(negedge clk);valid=0;sec_end=1;
   @(negedge clk);sec_end=0;
   wait(ready);repeat(3)@(negedge clk);
   cases=cases+1;
  end
  $display("PASS: BMP rejected %0d malformed/header/extent cases without write_req or pixel output",cases);$finish;
 end
 initial begin #1000000;$fatal(1,"invalid BMP timeout case=%0d",n);end
endmodule
