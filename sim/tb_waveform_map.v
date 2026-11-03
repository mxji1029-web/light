`timescale 1ns/1ps
// Independent perceptual display oracle: quantize magnitude in 512-LSB bins,
// sqrt-compress to 19px using 24576 as the nominal full-scale display reference.
module tb_waveform_map;
reg clk=0,rst=1;reg signed[15:0] sample=0;
wire ho,vo,de;wire[23:0] rgb;
always #5 clk=~clk;
audio_waveform_overlay dut(clk,rst,1'b1,1'b1,1'b0,24'd0,1'b0,sample,1'b0,ho,vo,de,rgb);
integer s,magnitude,bin,expected,got,previous;
initial begin
 #12;rst=0;
 for(s=-32768;s<=32767;s=s+1)begin
  sample=s;magnitude=s<0?-s:s;bin=magnitude/512;
  expected=$rtoi(19.0*$sqrt(bin/48.0)+0.5);
  if(expected>19)expected=19;
  if(s<0)expected=-expected;
  #1;got=$signed(dut.point);
  if(got!==expected)$fatal(1,"display map sample %0d got %0d expected %0d",s,got,expected);
 end
 sample=0;#1;if($signed(dut.point)!=0)$fatal(1,"silence should be flat");
 $display("PASS 65536 PCM values: perceptual mapping, +/-19 bounds, zero, sign symmetry");$finish;
end
endmodule
