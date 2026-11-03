`timescale 1ns/1ps
module tb_spectrum_bins;
reg clk=0,rst=1,av=0;reg signed[15:0] sample=0;
always #5 clk=~clk;
wire ho,vo,de;wire[23:0] rgb;
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) dut(clk,rst,1'b1,1'b1,1'b0,24'd0,av,sample,1'b0,ho,vo,de,rgb);
reg[15:0] samples[0:29695];reg[31:0] magnitudes[0:463];reg[5:0] levels[0:463];
integer b,n,j,blocks=0;
initial begin
 $readmemh("../material/spectrum_bars_20261022/samples.hex",samples);
 $readmemh("../material/spectrum_bars_20261022/magnitudes.hex",magnitudes);
 $readmemh("../material/spectrum_bars_20261022/levels.hex",levels);
 for(b=0;b<29;b=b+1)begin
  // The last 8 song blocks form one continuous DC/filter stream, no reset.
  if(b<=21)begin rst=1;repeat(3)@(negedge clk);rst=0;end
  for(n=0;n<1024;n=n+1)begin
   @(negedge clk);av=1;sample=samples[b*1024+n];
   @(negedge clk);av=0;repeat(126)@(negedge clk);
  end
  if(dut.overrun || dut.state!=0 || dut.sample_count!=0)$fatal(1,"engine missed input or failed block publication");
  for(j=0;j<16;j=j+1)begin
   if(dut.raw_magnitude[j]!==magnitudes[b*16+j])$fatal(1,"block%0d bin%0d magnitude got%0d expected%0d",b,j,dut.raw_magnitude[j],magnitudes[b*16+j]);
   if(dut.raw_level[j]!==levels[b*16+j])$fatal(1,"block%0d bin%0d height got%0d expected%0d",b,j,dut.raw_level[j],levels[b*16+j]);
  end
  blocks=blocks+1;
 end
 $display("PASS 29 spectrum blocks/464 magnitudes and heights: all16 tones, DC, silence, two-tone, full-scale, noise, real song; no overruns");$finish;
end
endmodule
