`timescale 1ns/1ps
// Whole-frame checker: BMP file byte order, padding, centering and exact Q8 pixels.
module tb_bmp_scale_quality;
 parameter SW=5, SH=7, TW=13, TH=9, TOP_DOWN=0, OFFSET=503;
 localparam STRIDE=(SW*3+3)/4*4;
 localparam BYTES=(OFFSET+STRIDE*SH+511)/512*512;
 localparam BASE=32'd41;
 reg clk=0, rst=1, start=0;
 always #5 clk=~clk;
 wire done, request, valid;
 wire [31:0] address;
 wire [23:0] pixel;
 reg [7:0] data=0;
 reg data_valid=0, sector_end=0;
 reg [7:0] source[0:BYTES-1];
 reg [23:0] expected[0:TW*TH-1];
 reg [2047:0] vector_dir;
`ifdef OLD_NEAREST
 bmp_scale_stream dut(
`else
 bmp_scale_quality dut(
`endif
 .clk(clk),.rst(rst),.start(start),.base_sector(BASE),.pixel_offset(OFFSET),
 .source_width(SW[10:0]),.source_height(SH[10:0]),.source_top_down(TOP_DOWN[0]),
 .target_width(TW[15:0]),.target_height(TH[15:0]),.done(done),
 .sd_sec_read(request),.sd_sec_read_addr(address),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(sector_end),
 .pixel_valid(valid),.pixel_data(pixel));
 integer sd_state=0, index=0, sector_base=0, cycles=0, count=0, requests=0,last_pixel_cycle=-4;
 reg transfer_gap=0;
 always @(posedge clk) begin
  data_valid<=0;sector_end<=0;
  if(rst)begin sd_state<=0;index<=0;transfer_gap<=0;end
  else case(sd_state)
   0:if(request)begin
    if(address<BASE || (address-BASE)*512>=BYTES) $fatal(1,"out of image sector %0d",address);
    sector_base<=(address-BASE)*512;index<=0;sd_state<=1;requests<=requests+1;
   end
   1:begin
    // Model arbitrary byte gaps rather than continuous ROM delivery.
    transfer_gap<=!transfer_gap;
    if(!transfer_gap)begin
     data<=source[sector_base+index];data_valid<=1;
     if(index==511)sd_state<=2;else index<=index+1;
    end
   end
   2:begin sector_end<=1;sd_state<=3;end
   3:if(!request)sd_state<=0;
  endcase
 end
 always @(negedge clk)if(!rst)begin
  cycles=cycles+1;
  if(valid)begin
   if(cycles-last_pixel_cycle<4)$fatal(1,"unsafe output rate: gap=%0d",cycles-last_pixel_cycle);
   last_pixel_cycle=cycles;
   if(count>=TW*TH)$fatal(1,"extra pixel");
   if(pixel!==expected[count])$fatal(1,"pixel=%0d x=%0d bottom_y=%0d got=%06x expected=%06x",count,count%TW,count/TW,pixel,expected[count]);
   count=count+1;
  end
  if(done)begin
   if(!valid || count!=TW*TH)$fatal(1,"done must accompany last pixel: count=%0d valid=%b",count,valid);
   if(request)$fatal(1,"sector request active at completion");
   $display("PASS bmp_scale_quality %0dx%0d -> %0dx%0d top_down=%0d pixels=%0d cycles=%0d sectors=%0d",SW,SH,TW,TH,TOP_DOWN,count,cycles,requests);
   repeat(5)begin @(negedge clk);if(valid||done)$fatal(1,"activity after completion");end
   $finish;
  end
  if(cycles>50000000)$fatal(1,"timeout count=%0d",count);
 end
 initial begin
  if(!$value$plusargs("vectors=%s",vector_dir))$fatal(1,"missing vectors directory");
  $readmemh({vector_dir,"/input.hex"},source);
  $readmemh({vector_dir,"/expected.hex"},expected);
  repeat(4)@(negedge clk);rst=0;
  @(negedge clk);start=1;@(negedge clk);start=0;
 end
endmodule
