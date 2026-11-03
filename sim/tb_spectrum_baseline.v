`timescale 1ns/1ps
module tb_spectrum_baseline;
reg clk=0,rst=1,vs=1,de=0;reg[23:0] rgb=24'h123456;
wire ho,vo,dout;wire[23:0] out;
always #5 clk=~clk;
audio_waveform_overlay dut(clk,rst,1'b1,vs,de,rgb,1'b0,16'sd0,1'b0,ho,vo,dout,out);
integer x,y;
initial begin
 repeat(3)@(negedge clk);rst=0;vs=0;repeat(3)@(negedge clk);vs=1;
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)begin
   @(negedge clk);de=1;@(posedge clk);#1;
   if(out!==((y==478 && x>=64 && x<576)?24'h806444:rgb))
    $fatal(1,"silent spectrum must have only common bottom baseline: x%0d y%0d got%h",x,y,out);
   if(!ho || !vo || !dout)$fatal(1,"spectrum video sync alignment");
  end
  @(negedge clk);de=0;repeat(3)@(negedge clk);
 end
 $display("PASS bottom-aligned silent spectrum: 307200 pixels, one-cycle sync, no middle axis");$finish;
end
endmodule
