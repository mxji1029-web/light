`timescale 1ns/1ps
module tb_spectrum_raster;
reg clk=0,rst=1,vs=1,de=0;reg[23:0] photo=0;
always #5 clk=~clk;
wire ho,vo,od;wire[23:0] rgb;
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) dut(clk,rst,1'b1,vs,de,photo,1'b0,16'sd0,1'b0,ho,vo,od,rgb);
integer x,y,j,f,h,p,up,col,localx,checked=0;reg[23:0] expected;
task snapshot;begin @(negedge clk);vs=0;repeat(3)@(negedge clk);vs=1;repeat(3)@(negedge clk);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(j=0;j<16;j=j+1)dut.raw_level[j]=(j*5)%40;
 snapshot;
 for(f=0;f<2;f=f+1)begin
  for(y=0;y<480;y=y+1)begin
   if(y==240)for(j=0;j<16;j=j+1)dut.raw_level[j]=0;
   for(x=0;x<640;x=x+1)begin
    @(negedge clk);de=1;photo={y[7:0],x[7:0],8'h39};expected=photo;
    if(x>=64 && x<576 && y>=440 && y<=478)begin
     col=(x-64)/32;localx=(x-64)%32;h=(col*5)%40;p=h;
     if(f==1)h=h>2?h-2:0;
     up=478-y;
     if(y==478)expected=24'h806444;
     if(localx>=4 && localx<28)begin
      if(h>0 && up<h)expected=up+3>=h?24'hf5d393:up>=22?24'he9bd78:up>=10?24'hcda261:24'ha67b47;
      if(p>0 && up==p-1)expected=24'hf5d393;
     end
    end
    @(posedge clk);#1;
    if(rgb!==expected || !ho || !vo || !od)$fatal(1,"raster frame%0d x%0d y%0d got%h expected%h",f,x,y,rgb,expected);
    checked=checked+1;
   end
   @(negedge clk);de=0;repeat(4)@(negedge clk);
  end
  snapshot;
 end
 $display("PASS spectrum raster: %0d exact pixels; common bottom, gradient, gaps, peak caps, frame snapshot, 2px release",checked);$finish;
end
endmodule
