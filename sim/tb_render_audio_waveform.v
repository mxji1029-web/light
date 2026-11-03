`timescale 1ns/1ps
module tb_render_audio_waveform;
reg clk=0,rst=1,vs=1,de=0,av=0;
reg[23:0] photo=0,position=0;reg signed[15:0] sample=0;
wire lh,lv,ld,wh,wv,wd;wire[23:0] lr,wr;
reg[23:0] image[0:307199],positions[0:16];reg[15:0] audio[0:139263];
always #5 clk=~clk;
lyric_overlay lyric(clk,rst,1'b1,vs,de,photo,position,8'd100,lh,lv,ld,lr);
audio_waveform_overlay waveform(clk,rst,lh,lv,ld,lr,av,sample,1'b0,wh,wv,wd,wr);
integer frame,i,x,y,file,pixels;reg capture=0;reg[255:0] filename;
always @(posedge clk)begin
 #1;if(capture && wd)begin
  $fwrite(file,"%c%c%c",wr[23:16],wr[15:8],wr[7:0]);pixels=pixels+1;
 end
end
initial begin
 $readmemh("photo.hex",image);$readmemh("audio.hex",audio);$readmemh("positions.hex",positions);
 #12;rst=0;
 for(frame=0;frame<17;frame=frame+1)begin
  for(i=0;i<8192;i=i+1)begin
   @(negedge clk);av=1;sample=audio[frame*8192+i];
   @(negedge clk);av=0;
  end
  position=positions[frame];@(negedge clk);vs=0;repeat(8)@(negedge clk);
  vs=1;repeat(240)@(negedge clk);
  $sformat(filename,"waveform_frame_%02d.ppm",frame);file=$fopen(filename,"wb");
  $fwrite(file,"P6\n640 480\n255\n");pixels=0;capture=1;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin @(negedge clk);de=1;photo=image[y*640+x];end
   @(negedge clk);de=0;repeat(8)@(negedge clk);
  end
  repeat(5)@(negedge clk);capture=0;$fclose(file);
  if(pixels!=307200)$fatal(1,"preview DE alignment produced %0d pixels",pixels);
 end
 $display("PASS 17 real-song waveform/lyric/photo frames from production RTL");$finish;
end
endmodule
