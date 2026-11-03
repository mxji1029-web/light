`timescale 1ns/1ps
module tb_audio_waveform;
reg clk=0,rst=1,vs=1,de=0,paused=0,valid=0;
reg signed[15:0] sample=0;reg[23:0] rgb=0;
wire ho,vo,dout;wire[23:0] out;
always #5 clk=~clk;
audio_waveform_overlay dut(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(de),.rgb(rgb),
 .audio_valid(valid),.audio_sample(sample),.paused(paused),
 .hs_out(ho),.vs_out(vo),.de_out(dout),.rgb_out(out));
integer x,y,j,k,amp,ordinate,checked=0;reg[23:0] expected;
function integer display_height;input integer raw;integer bin_count;begin
 bin_count=(raw<0?-raw:raw)/512;
 display_height=$rtoi(19.0*$sqrt(bin_count/48.0)+0.5);
 if(display_height>19)display_height=19;
end endfunction
task push;input integer value;begin
 @(negedge clk);sample=value;valid=1;
 @(negedge clk);valid=0;sample=-32768;
end endtask
task history;input integer mode;begin
 for(j=0;j<128;j=j+1)begin
  amp=mode==1?j%13:mode==2?32:mode==3?8:0;
  for(k=0;k<64;k=k+1)push(mode==3?8192 : k<32 ? (amp==32?32767:amp*1024) : -amp*1024);
 end
end endtask
task snapshot;begin
 @(negedge clk);vs=0;repeat(4)@(negedge clk);vs=1;repeat(4)@(negedge clk);
end endtask
task render;input integer mode;input change_during_frame;begin
 for(y=0;y<480;y=y+1)begin
  // Finish an entirely different waveform during blanking in the middle of
  // the frame: all remaining pixels must still use the original snapshot.
  if(change_during_frame && y==240)history(0);
  for(x=0;x<640;x=x+1)begin
   @(negedge clk);de=1;rgb={y[7:0],x[7:0],8'h39};expected=rgb;
   if(x>=64 && x<576 && y>=440 && y<=478 && (x%4)!=3)begin
    amp=mode==1?display_height((((x-64)/4)%13)*1024):mode==2?19:mode==3?display_height(8192):0;
    ordinate=459-y;
    if(mode==3 ? ordinate==display_height(8192) : ordinate>=-amp && ordinate<=amp)expected=24'he9bd78;
   end
   @(posedge clk);#1;
   if(!ho || vo!==vs || !dout || out!==expected)
    $fatal(1,"wave pixel x%0d y%0d got %h expected %h",x,y,out,expected);
   checked=checked+1;
  end
  @(negedge clk);de=0;repeat(4)@(negedge clk);
  if(dout)$fatal(1,"DE not aligned with one-cycle RGB path");
 end
end endtask
initial begin
 #12;rst=0;
 snapshot;render(0,0);
 history(1);snapshot;render(1,1);
 snapshot;render(0,0);
 history(2);snapshot;render(2,0);
 paused=1;repeat(5)@(negedge clk);history(0);snapshot;render(2,0);
 paused=0;repeat(5)@(negedge clk);history(0);snapshot;render(0,0);
 // A unipolar/DC window must not invent a zero sample or fill to the axis.
 history(3);snapshot;render(3,0);
 $display("PASS waveform: %0d exact pixels; signed extrema, chronological bins, invalid samples, silence, pause, frame snapshot",checked);$finish;
end
endmodule
