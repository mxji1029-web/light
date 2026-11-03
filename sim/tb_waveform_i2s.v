`timescale 1ns/1ps
module tb_waveform_i2s;
reg audio_clk=0,video_clk=0,rst=1,paused=0;
always #40.667 audio_clk=~audio_clk;
always #20 video_clk=~video_clk;
wire bclk,lrck,dout,pop,tick,av;wire[23:0] left,right;
wire ho,vo,de;wire[23:0] rgb;
pcm_player_i2s player(.I_mclk(audio_clk),.I_rst(rst),.I_volume(8'd255),.I_pause(paused),
 .I_fifo_dout({-16'sd20000,16'sd20000}),.I_fifo_empty(1'b0),.O_fifo_re(pop),
 .I_voice_sample(16'sd0),.I_voice_active(1'b0),.O_sample_tick(tick),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(video_clk,rst,bclk,lrck,dout,av,left,right);
audio_waveform_overlay waveform(.clk(video_clk),.rst(rst),.hs(1'b1),.vs(1'b1),.de(1'b0),.rgb(24'd0),
 .audio_valid(av),.audio_sample(left[23:8]),.paused(paused),
 .hs_out(ho),.vs_out(vo),.de_out(de),.rgb_out(rgb));
integer received=0,i,before_pause;
reg signed[5:0] frozen_min[0:127],frozen_max[0:127];
always @(posedge video_clk)if(!rst && av)received=received+1;
initial begin
 repeat(5)@(negedge video_clk);rst=0;
 wait(received>=300);@(negedge video_clk);
 if(waveform.history_min[127]!==-6'sd15 || waveform.history_max[127]!==6'sd15)
  $fatal(1,"waveform did not receive correctly aligned signed PCM from actual I2S receiver");
 if(waveform.history_min[126]!==-6'sd15 || waveform.history_max[126]!==6'sd15)
  $fatal(1,"real I2S did not build multiple chronological buckets");
 paused=1;repeat(8)@(negedge video_clk);
 for(i=0;i<128;i=i+1)begin frozen_min[i]=waveform.history_min[i];frozen_max[i]=waveform.history_max[i];end
 before_pause=received;wait(received>=before_pause+80);@(negedge video_clk);
 for(i=0;i<128;i=i+1)
  if(waveform.history_min[i]!==frozen_min[i] || waveform.history_max[i]!==frozen_max[i])
   $fatal(1,"paused I2S zeros changed frozen waveform");
 $display("PASS real I2S player -> receiver -> signed waveform capture, stereo output and pause freeze");$finish;
end
initial begin #12000000;$fatal(1,"I2S waveform timeout");end
endmodule
