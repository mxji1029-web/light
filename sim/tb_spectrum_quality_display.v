`timescale 1ns/1ps
module tb_spectrum_quality_display;
 reg clk=0,rst=1,vs=1,de=0,paused=0,bv=0,silent=0;
 reg [8:0] bi=0;reg [31:0] bp=0;
 wire hs_out,vs_out,de_out,ready,overrun;wire [23:0] rgb_out;
 always #20 clk=~clk;
 audio_spectrum_display32 dut(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(de),.rgb(24'h123456),
  .paused(paused),.bin_valid(bv),.bin_index(bi),.bin_power(bp),.block_silent(silent),
  .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out),.block_ready(ready),.overrun(overrun));
 integer edges[0:32];integer expected_log[0:31];integer j,n,x,y,col,lx,up,h,p,painted=0;
 reg [23:0] want,ink;reg [5:0] frozen[0:63];reg [9:0] frozen_ref;
 task frame;begin
  @(negedge clk);vs=0;repeat(3)@(negedge clk);vs=1;repeat(3)@(negedge clk);
 end endtask
 task feed_bins;input integer fixture;begin
  for(n=0;n<512;n=n+1)begin
   @(negedge clk);bv=1;bi=n;bp=0;
   if(fixture==0)begin
    if(n==0)bp=65538;
    if(n==1)bp=131074;
    if(n==511)bp=16544;
   end else if(fixture==1)bp=10000;
   else if(fixture==2 && n==0)bp=16777218;
  end
  @(negedge clk);bv=0;wait(ready);@(negedge clk);
 end endtask
 initial begin
  edges[0]=1;edges[1]=2;edges[2]=3;edges[3]=4;edges[4]=5;edges[5]=6;edges[6]=7;edges[7]=8;
  edges[8]=9;edges[9]=11;edges[10]=13;edges[11]=15;edges[12]=18;edges[13]=21;edges[14]=25;
  edges[15]=29;edges[16]=35;edges[17]=41;edges[18]=49;edges[19]=57;edges[20]=68;edges[21]=80;
  edges[22]=95;edges[23]=113;edges[24]=133;edges[25]=158;edges[26]=187;edges[27]=221;
  edges[28]=261;edges[29]=309;edges[30]=366;edges[31]=433;edges[32]=513;
  // Independently generated Q4 logs of (bandwidth * (10000 - 2)).
  expected_log[0]=211;expected_log[1]=211;expected_log[2]=211;expected_log[3]=211;
  expected_log[4]=211;expected_log[5]=211;expected_log[6]=211;expected_log[7]=211;
  expected_log[8]=227;expected_log[9]=227;expected_log[10]=227;expected_log[11]=237;
  expected_log[12]=237;expected_log[13]=243;expected_log[14]=243;expected_log[15]=253;
  expected_log[16]=253;expected_log[17]=259;expected_log[18]=259;expected_log[19]=266;
  expected_log[20]=269;expected_log[21]=274;expected_log[22]=277;expected_log[23]=280;
  expected_log[24]=286;expected_log[25]=289;expected_log[26]=292;expected_log[27]=296;
  expected_log[28]=301;expected_log[29]=305;expected_log[30]=308;expected_log[31]=312;
  repeat(4)@(negedge clk);rst=0;
  feed_bins(0);frame;
  if(dut.display_level[0]!==30 || dut.display_level[1]!==34 || dut.display_level[31]!==24)
   $fatal(1,"calibrated 36dB map/boundary failed %d %d %d",dut.display_level[0],dut.display_level[1],dut.display_level[31]);
  for(j=2;j<31;j=j+1)if(dut.display_level[j]!==0)$fatal(1,"empty band invented motion %d",j);
  feed_bins(1);
  for(j=0;j<32;j=j+1)
   if(dut.work_log[j]!==expected_log[j])$fatal(1,"band %d missing/repeated FFT bins",j);
  feed_bins(2);frame;
  if(dut.display_level[0]!==36)$fatal(1,"fast attack/headroom failed");
  for(j=0;j<32;j=j+1)begin frozen[j]=dut.display_level[j];frozen[32+j]=dut.display_peak[j];end
  frozen_ref=dut.reference_q4;paused=1;repeat(20)frame;
  if(dut.reference_q4!==frozen_ref)$fatal(1,"paused reference moved");
  for(j=0;j<32;j=j+1)
   if(dut.display_level[j]!==frozen[j] || dut.display_peak[j]!==frozen[32+j])$fatal(1,"paused bar/peak moved");
  // Independently check the complete frozen raster with 32 columns.
  frame;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;@(posedge clk);#1;
    want=24'h123456;
    if(y==478 && x>=64 && x<576)want=24'h806444;
    if(x>=64 && x<576 && y>=440 && y<=478)begin
     col=(x-64)/16;lx=(x-64)%16;up=478-y;h=frozen[col];p=frozen[32+col];
     if(lx>=3 && lx<13 && ((h!=0 && up<h)||(p!=0 && up==p-1)))begin
      ink=(p!=0 && up==p-1)||(h!=0 && up<h && up+3>=h)?24'hf5d393:
          up>=22?24'he9bd78:up>=10?24'hcda261:24'ha67b47;
      want=ink;painted=painted+1;
     end
    end
    if(rgb_out!==want || !de_out || !hs_out || !vs_out)$fatal(1,"32-column raster/sync %d,%d got%h want%h",x,y,rgb_out,want);
   end
   @(negedge clk);de=0;repeat(3)@(negedge clk);
  end
  paused=0;silent=1;feed_bins(2);
  for(j=0;j<32;j=j+1)if(dut.raw_level[j]!==0)$fatal(1,"silence gate failed");
  frame;if(dut.display_level[0]!==32)$fatal(1,"release must fall4 pixels/frame");
  repeat(8)frame;if(dut.display_level[0]!==0)$fatal(1,"release failed to reach baseline");
  if(overrun)$fatal(1,"postprocessor overrun");
  $display("PASS 32-band coverage bin1..512, calibrated map, silence, fast attack/4px release, pause, 307200 raster pixels/%0d painted",painted);$finish;
 end
 initial begin #100000000;$fatal(1,"display test timeout");end
endmodule
