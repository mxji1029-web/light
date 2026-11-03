`timescale 1ns/1ps
module tb_spectrum_pause;
reg audio_clk=0,video_clk=0,rst=1,paused=0,vs=1;
always #40.667 audio_clk=~audio_clk;always #20 video_clk=~video_clk;
reg[15:0] tone[0:1023];reg[9:0] address=0;
wire bclk,lrck,dout,pop,tick,av;wire[23:0] left,right;
wire[9:0] next_address=address+10'd1;
always @(posedge audio_clk)if(rst)address<=0;else if(pop)address<=address+10'd2;
pcm_player_i2s player(.I_mclk(audio_clk),.I_rst(rst),.I_volume(8'd255),.I_pause(paused),
 .I_fifo_dout({tone[next_address],tone[address]}),.I_fifo_empty(1'b0),.O_fifo_re(pop),
 .I_voice_sample(16'sd0),.I_voice_active(1'b0),.O_sample_tick(tick),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(video_clk,rst,bclk,lrck,dout,av,left,right);
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) dut(.clk(video_clk),.rst(rst),.hs(1'b1),.vs(vs),.de(1'b0),.rgb(24'd0),
 .audio_valid(av),.audio_sample(left[23:8]),.paused(paused));
integer received=0,blocks=0,i,before_pause;reg[5:0] levels[0:15],peaks[0:15];
always @(posedge video_clk)if(!rst)begin
 if(av)received=received+1;
 if(dut.block_ready)blocks=blocks+1;
end
task frame;begin
 @(negedge video_clk);vs=0;repeat(3)@(negedge video_clk);
 vs=1;repeat(12)@(negedge video_clk);
end endtask
initial begin
 $readmemh("../material/spectrum_bars_20261022/tone.hex",tone);
 repeat(5)@(negedge video_clk);rst=0;wait(blocks>=2);frame;
 if(dut.display_level[8]==0)$fatal(1,"spectrum pause test did not establish nonzero display");
 paused=1;repeat(8)@(negedge video_clk);
 for(i=0;i<16;i=i+1)begin levels[i]=dut.display_level[i];peaks[i]=dut.display_peak[i];end
 before_pause=received;wait(received>=before_pause+80);
 repeat(30)frame;
 for(i=0;i<16;i=i+1)
  if(dut.display_level[i]!==levels[i] || dut.display_peak[i]!==peaks[i])
   $fatal(1,"paused spectrum bars or peak caps moved");
 paused=0;wait(blocks>=3);frame;
 if(dut.overrun || dut.display_level[8]==0)$fatal(1,"spectrum did not resume cleanly");
 $display("PASS spectrum pause: real PCM/I2S tone produces nonzero bars; all 16 levels/peak caps freeze across 80 silence samples and 30 frames, then resume");$finish;
end
initial begin #100000000;$fatal(1,"spectrum pause timeout");end
endmodule
