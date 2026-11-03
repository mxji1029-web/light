`timescale 1ns/1ps
// Actual photo/caption/spectrum RTL, 800x525 timing at25MHz and48k PCM cadence.
module tb_render_spectrum;
reg clk=0,rst=1,hs=1,vs=1,de=0,av=0;reg[23:0] photo=0;reg signed[15:0] sample=0;
always #20 clk=~clk;
reg[23:0] image[0:307199];reg[15:0] audio[0:139263];
integer audio_index=0,sample_divider=0;
wire lh,lv,ld,oh,ov,od;wire[23:0] lr,out;
wire[23:0] position=24'd2832000+audio_index;
lyric_overlay lyric(clk,rst,hs,vs,de,photo,position,8'd100,lh,lv,ld,lr);
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) spectrum(clk,rst,lh,lv,ld,lr,av,sample,1'b0,oh,ov,od,out);
always @(negedge clk)begin
 if(rst)begin sample_divider=0;audio_index=0;av=0;end
 else if(sample_divider==520)begin sample_divider=0;av=1;sample=audio[audio_index];audio_index=audio_index+1;end
 else begin sample_divider=sample_divider+1;av=0;end
end
integer frame,x,y,fd,pixels,trace,j;reg capture=0;reg[255:0] name;
always @(posedge clk)begin
 #1;if(capture && od)begin
  $fwrite(fd,"%c%c%c",out[23:16],out[15:8],out[7:0]);pixels=pixels+1;
 end
end
initial begin
 $readmemh("../audio_waveform_large_20261022/photo.hex",image);
 $readmemh("../audio_waveform_large_20261022/audio.hex",audio);
 trace=$fopen("levels.csv","w");
 repeat(4)@(negedge clk);rst=0;
 for(frame=0;frame<24;frame=frame+1)begin
  $sformat(name,"frame_%02d.ppm",frame);fd=$fopen(name,"wb");$fwrite(fd,"P6\n640 480\n255\n");pixels=0;capture=1;
  for(y=-45;y<480;y=y+1)begin
   for(x=-160;x<640;x=x+1)begin
    @(negedge clk);hs=x>= -64;vs=y>= -43;de=x>=0 && y>=0;
    photo=de?image[y*640+x]:24'd0;
   end
  end
  @(negedge clk);de=0;repeat(8)@(negedge clk);capture=0;$fclose(fd);
  if(pixels!=307200 || spectrum.overrun)$fatal(1,"preview frame incomplete/overrun");
  $fwrite(trace,"%0d",frame);for(j=0;j<16;j=j+1)$fwrite(trace,",%0d",spectrum.display_level[j]);
  for(j=0;j<16;j=j+1)$fwrite(trace,",%0d",spectrum.display_peak[j]);$fwrite(trace,"\n");
 end
 $fclose(trace);$display("PASS 24 actual photo/caption/spectrum frames at25MHz/800x525,48k PCM cadence, no overrun");$finish;
end
endmodule
