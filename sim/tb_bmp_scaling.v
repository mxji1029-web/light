`timescale 1ns/1ps
// Byte-level SD responder plus independently computed coordinate oracle.
module tb_bmp_scaling;
 parameter SW=320,SH=240,TOP_DOWN=0,OFFSET=54,GAPPED=0,END_WITH_DATA=0,QUALITY=1;
 parameter INPUT_HEX="",OUTPUT_PPM="",CHECK_PATTERN=1;
 localparam FW=(SW*480>SH*640)?640:((SW*480/SH)>0?(SW*480/SH):1);
 localparam FH=(SW*480>SH*640)?((SH*640/SW)>0?(SH*640/SW):1):480;
 localparam LEFT=(640-FW)/2,TOP=(480-FH)/2;
 localparam STRIDE=((SW*3+3)/4)*4;
 localparam LENGTH=OFFSET+STRIDE*SH;
 reg clk=0,rst=1,start=0,ack=0,valid=0,sec_end=0;
 always #5 clk=~clk;
 reg [7:0] data=0;
 wire ready,wr,req,pv;
 wire [31:0] addr;
 wire [23:0] pixel;
 reg [7:0] mem[0:LENGTH+511];
 integer i,x,y,k,b,source_x,source_y,pixels=0,requests=0;
 integer output_fd=0;
 reg [23:0] expected;
 reg [31:0] signed_height;
 function [23:0] pattern;
  input integer xx,yy;
  begin pattern={8'((xx*3+yy*7)%256),8'((xx*11+yy*5)%256),8'((xx^yy)%256)};end
 endfunction
 task put32;input integer index;input [31:0] value;
  begin mem[index]=value[7:0];mem[index+1]=value[15:8];mem[index+2]=value[23:16];mem[index+3]=value[31:24];end
 endtask
 bmp_read #(.SCALE_QUALITY(QUALITY)) dut(.clk(clk),.rst(rst),.ready(ready),.scan_start(1'b0),.scan_start_sector(32'd0),
  .scan_max_sector(32'd0),.scan_target_count(7'd0),.load_start(start),.load_sector(32'd123),
  .sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),.write_req(wr),.write_req_ack(ack),
  .sd_sec_read(req),.sd_sec_read_addr(addr),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),
  .sd_sec_read_end(sec_end),.bmp_data_wr_en(pv),.bmp_data(pixel));
 function [23:0] quality_reference;
  input integer xx,yy;
  integer cx,cy,sx,sy,fx,fy,ch,h0,h1,blend;
  reg [23:0] a,b,c,d,v;
  begin
   v=0;
   if(xx>=LEFT && xx<LEFT+FW && yy>=TOP && yy<TOP+FH)begin
    cx=xx-LEFT;cy=yy-TOP;
    sx=cx*SW/FW;sy=cy*SH/FH;
    fx=((cx*SW)%FW)*256/FW;fy=((cy*SH)%FH)*256/FH;
    a=pattern(sx,sy);b=pattern((sx+1<SW)?sx+1:sx,sy);
    c=pattern(sx,(sy+1<SH)?sy+1:sy);
    d=pattern((sx+1<SW)?sx+1:sx,(sy+1<SH)?sy+1:sy);
    for(ch=0;ch<3;ch=ch+1)begin
     h0=(((a>>(ch*8))&255)*(256-fx)+((b>>(ch*8))&255)*fx+128)>>8;
     h1=(((c>>(ch*8))&255)*(256-fx)+((d>>(ch*8))&255)*fx+128)>>8;
     blend=(h0*(256-fy)+h1*fy+128)>>8;v[ch*8+:8]=blend;
    end
   end
   quality_reference=v;
  end
 endfunction
 always @(posedge clk)begin
  #1;
  if(pv)begin
   if(pixels>=640*480)$fatal(1,"too many output pixels");
   // Writer reverses the emitted rows; always emit bottom-up destination rows.
   source_x=((pixels%640)*SW)/640;
   source_y=((479-pixels/640)*SH)/480;
   expected=QUALITY?quality_reference(pixels%640,479-pixels/640):pattern(source_x,source_y);
   if(CHECK_PATTERN && pixel!==expected)$fatal(1,"pixel %0d wanted %h got %h source=(%0d,%0d)",pixels,expected,pixel,source_x,source_y);
   if(output_fd)$fwrite(output_fd,"%c%c%c",pixel[23:16],pixel[15:8],pixel[7:0]);
   pixels=pixels+1;
  end
 end
 initial begin : sd_responder
  wait(!rst);
  forever begin
   wait(req);
   k=(addr-123)*512;
   if(addr<123 || k>LENGTH)$fatal(1,"out-of-file sector %0d",addr);
   requests=requests+1;
   for(b=0;b<512;b=b+1)begin
    if(GAPPED && b%7==3)begin @(negedge clk);valid=0;end
    @(negedge clk);valid=1;data=mem[k+b];
    if(END_WITH_DATA && b==511)sec_end=1;
   end
   @(negedge clk);valid=0;sec_end=END_WITH_DATA?0:1;
   @(negedge clk);sec_end=0;
   wait(!req);
  end
 end
 initial begin
  for(i=0;i<LENGTH+512;i=i+1)mem[i]=8'he7;
  for(i=0;i<54;i=i+1)mem[i]=0;
  mem[0]="B";mem[1]="M";put32(2,LENGTH);put32(10,OFFSET);put32(14,40);put32(18,SW);
  signed_height=TOP_DOWN?-SH:SH;put32(22,signed_height);mem[26]=1;mem[28]=24;put32(30,0);
  for(y=0;y<SH;y=y+1)for(x=0;x<SW;x=x+1)begin
   expected=pattern(x,TOP_DOWN?y:SH-1-y);
   i=OFFSET+y*STRIDE+x*3;
   mem[i]=expected[7:0];mem[i+1]=expected[15:8];mem[i+2]=expected[23:16];
  end
  if(INPUT_HEX!="")$readmemh(INPUT_HEX,mem);
  if(OUTPUT_PPM!="")begin
   output_fd=$fopen(OUTPUT_PPM,"wb");
   if(!output_fd)$fatal(1,"cannot create raster output");
   $fwrite(output_fd,"P6\n640 480\n255\n");
  end
  repeat(5)@(negedge clk);rst=0;
  @(negedge clk);start=1;
  @(negedge clk);start=0;
  wait(wr);repeat(3)@(negedge clk);ack=1;
  wait(!wr);@(negedge clk);ack=0;
  wait(ready);repeat(3)@(negedge clk);
  if(pixels!=307200)$fatal(1,"wrong pixel count %0d",pixels);
  if(output_fd)$fclose(output_fd);
  $display("PASS: BMP scale %0dx%0d quality=%0d topdown=%0d offset=%0d gaps=%0d pixels=%0d sectors=%0d",SW,SH,QUALITY,TOP_DOWN,OFFSET,GAPPED,pixels,requests);
  $finish;
 end
 // Worst-size Q8 resampling uses ~0.21 s even with zero card latency.
 // Keep a finite 0.5 s unit-test limit; the separate 25 MHz shared-card
 // test exercises the unchanged 2.684 s production watchdog budget.
 initial begin #500000000;$fatal(1,"scaler timeout pixels=%0d requests=%0d ready=%b",pixels,requests,ready);end
endmodule
