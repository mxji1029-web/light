`timescale 1ns/1ps
// Complete display chain, actual key controller and an independent old-chain
// reference. Default output must remain bit-exact even when settings change
// halfway through a frame; only the following frame may apply them.
module tb_picture_pipeline;
reg clk=0,rst=1,vs=1,de=0,kn=1,ka=1,kp=1,av=0;
reg[23:0] photo=0;reg signed[15:0] sample=0;
wire nav,auto_n,active,pause_toggle;wire[1:0] selected;wire[3:0] volume_level;
wire signed[7:0] brightness,frame_brightness;
wire[2:0] contrast,frame_contrast;
wire frame_active,frame_selected;
wire ah,as,ad,lh,ls,ld,wh,ws,wd,oh,os,od;
wire olh,ols,old,owh,ows,owd;
wire[23:0] ar,lr,wr,orr,olr,owr;
reg[23:0] image[0:307199];reg[15:0] audio[0:139263];
always #5 clk=~clk;
picture_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.HOLD_MS(20)) keys(
 clk,rst,kn,ka,kp,nav,auto_n,active,selected,brightness,contrast,pause_toggle,volume_level);
photo_adjust adjust(clk,rst,1'b1,vs,de,photo,brightness,contrast,active,selected[0],
 ah,as,ad,ar,frame_brightness,frame_contrast,frame_active,frame_selected);
lyric_overlay lyric(clk,rst,ah,as,ad,ar,24'd2832000,8'd100,lh,ls,ld,lr);
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) wave(clk,rst,lh,ls,ld,lr,av,sample,1'b0,wh,ws,wd,wr);
picture_settings_osd osd(clk,rst,wh,ws,wd,wr,frame_active,{1'b0,frame_selected},frame_brightness,frame_contrast,oh,os,od,orr,4'd10);
lyric_overlay old_lyric(clk,rst,1'b1,vs,de,photo,24'd2832000,8'd100,olh,ols,old,olr);
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) old_wave(clk,rst,olh,ols,old,olr,av,sample,1'b0,owh,ows,owd,owr);
reg[23:0] old_d0,old_d1,old_d2;reg[2:0] sync_d0,sync_d1,sync_d2;
reg capture=0,compare_identity=0;
integer file,pixels,identity_pixels=0,frame,x,y,i;
reg[255:0] filename;
always @(posedge clk)begin
 old_d0<=owr;old_d1<=old_d0;old_d2<=old_d1;
 sync_d0<={owh,ows,owd};sync_d1<=sync_d0;sync_d2<=sync_d1;
 #1;
 if(capture && od)begin
  if({oh,os,od}!==sync_d2)$fatal(1,"new pipeline sync not aligned with old +3 clocks");
  if(compare_identity)begin
   if(orr!==old_d2)$fatal(1,"default frame changed after adding picture controls");
   identity_pixels=identity_pixels+1;
  end
  if((^orr)===1'bx)$fatal(1,"unknown pixel in settings pipeline");
  $fwrite(file,"%c%c%c",orr[23:16],orr[15:8],orr[7:0]);pixels=pixels+1;
 end
end
task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
task tap;input integer which;begin
 if(which==0)kn=0;else if(which==1)ka=0;else kp=0;
 tick(8);kn=1;ka=1;kp=1;tick(8);
end endtask
initial begin
 $readmemh("../audio_waveform_large_20261022/photo.hex",image);
 $readmemh("../audio_waveform_large_20261022/audio.hex",audio);
 #12;rst=0;
 for(frame=0;frame<3;frame=frame+1)begin
  if(frame==2)begin repeat(4)tap(0);tap(2);tap(1);end
  for(i=0;i<8192;i=i+1)begin
   @(negedge clk);av=1;sample=audio[frame*8192+i];@(negedge clk);av=0;tick(126);
  end
  @(negedge clk);vs=0;tick(8);vs=1;tick(260);
  if(frame==0 && (frame_brightness!=0 || frame_contrast!=2 || frame_active))$fatal(1,"bad default frame");
  if(frame==1 && (frame_brightness!=32 || frame_contrast!=2 || !frame_active))$fatal(1,"brightness mode not applied");
  if(frame==2 && (frame_brightness!=0 || frame_contrast!=3 || !frame_active || !frame_selected))$fatal(1,"contrast mode not applied");
  $sformat(filename,"settings_frame_%02d.ppm",frame);file=$fopen(filename,"wb");
  $fwrite(file,"P6\n640 480\n255\n");pixels=0;capture=1;compare_identity=frame==0;
  for(y=0;y<480;y=y+1)begin
   if(frame==0 && y==240)begin
    kp=0;tick(35);kp=1;tick(10);repeat(4)tap(1);
    if(!active || brightness!=32)$fatal(1,"actual key setup failed");
   end
   for(x=0;x<640;x=x+1)begin @(negedge clk);de=1;photo=image[y*640+x];end
   @(negedge clk);de=0;tick(10);
  end
  tick(8);capture=0;$fclose(file);
  if(pixels!=307200)$fatal(1,"complete pipeline pixel count %0d",pixels);
 end
 if(identity_pixels!=307200)$fatal(1,"default photo did not get a complete bit-exact comparison");
 $display("PASS complete keys/photo/lyric/wave/OSD pipeline: 921600 pixels, 307200 default identity pixels, mid-frame setting changes deferred");$finish;
end
endmodule
