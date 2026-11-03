`timescale 1ns/1ps
// Bound per-frame movement at the actual ~59.5 Hz / 48 kHz sample cadence.
// This catches large position jumps that make high-contrast text trail on LCDs.
module tb_lyric_motion;
reg clk=0,rst=1,vs=1;
reg[23:0] position=0; reg[7:0] level=255;
wire hs_o,vs_o,de_o;wire[23:0] rgb_o;
always #5 clk=~clk;
lyric_overlay dut(clk,rst,1'b1,vs,1'b0,24'd0,position,level,hs_o,vs_o,de_o,rgb_o);
integer t,previous,offset,delta,max_delta=0,peak_quiet,peak_loud,a,b;
task sample; input integer age;begin
 position=24'd1371408+age;
 repeat(4)@(negedge clk);
 offset=$signed(dut.bounce);
end endtask
initial begin
 #12;rst=0;force dut.event_word=56'h6714ed101506c0;
 for(t=0;t<19000;t=t+806)begin
  sample(t);
  if(t>0)begin
   delta=offset-previous;if(delta<0)delta=-delta;
   if(delta>max_delta)max_delta=delta;
   if(delta>5)$fatal(1,"caption moved %0d pixels in one frame at age %0d",delta,t);
  end
  previous=offset;
 end
 level=0;sample(8192);peak_quiet=offset;
 level=255;sample(8192);peak_loud=offset;
 if(!(peak_loud<peak_quiet && peak_loud>=-8))$fatal(1,"audio-reactive lift missing or excessive");
 sample(18000);if(offset!=0)$fatal(1,"caption did not settle");
 // Sweep every possible sample phase and all 16 combinations of consecutive
 // volume bins, including sudden loud/quiet changes while the glyph is moving.
 for(t=0;t<17408;t=t+1)begin
  for(a=0;a<4;a=a+1)begin
   level=a*64;sample(t);previous=offset;
   for(b=0;b<4;b=b+1)begin
    level=b*64;sample(t+806);
    delta=offset-previous;if(delta<0)delta=-delta;
    if(delta>5)$fatal(1,"phase/volume jump %0d at age %0d bins %0d -> %0d",delta,t,a,b);
   end
  end
 end
 $display("PASS caption movement <=5 px/frame, audio-reactive peak %0d..%0d, settles once",peak_quiet,peak_loud);$finish;
end
endmodule
