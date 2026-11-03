`timescale 1ns/1ps
module tb_spectrum_i2s;
reg audio_clk=0,video_clk=0,rst=1;
always #40.667 audio_clk=~audio_clk;always #20 video_clk=~video_clk;
reg[15:0] tone[0:1023];reg[9:0] address=0;
wire bclk,lrck,dout,pop,tick,av;wire[23:0] left,right;
wire ho,vo,de;wire[23:0] rgb;
wire[9:0] next_address=address+10'd1;
always @(posedge audio_clk)if(rst)address<=0;else if(pop)address<=address+10'd2;
pcm_player_i2s player(.I_mclk(audio_clk),.I_rst(rst),.I_volume(8'd255),.I_pause(1'b0),
 .I_fifo_dout({tone[next_address],tone[address]}),.I_fifo_empty(1'b0),.O_fifo_re(pop),
 .I_voice_sample(16'sd0),.I_voice_active(1'b0),.O_sample_tick(tick),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(video_clk,rst,bclk,lrck,dout,av,left,right);
audio_waveform_overlay #(.SPECTRUM_QUALITY(0)) dut(video_clk,rst,1'b1,1'b1,1'b0,24'd0,av,left[23:8],1'b0,ho,vo,de,rgb);
integer received=0,blocks=0,i,winner;reg saw_positive=0,saw_negative=0;
always @(posedge video_clk)if(!rst)begin
 if(av)begin
  received=received+1;
  if($signed(left[23:8])>1000)saw_positive=1;
  if($signed(left[23:8])< -1000)saw_negative=1;
 end
 if(dut.block_ready)blocks=blocks+1;
end
initial begin
 $readmemh("../material/spectrum_bars_20261022/tone.hex",tone);
 repeat(5)@(negedge video_clk);rst=0;wait(blocks>=2);@(negedge video_clk);
 winner=0;for(i=1;i<16;i=i+1)if(dut.raw_magnitude[i]>dut.raw_magnitude[winner])winner=i;
 if(winner!=8 || dut.raw_magnitude[8]<10000 || dut.overrun || !saw_positive || !saw_negative)
  $fatal(1,"real I2S spectrum wrong: peak%0d magnitude%0d received%0d overrun%b",winner,dut.raw_magnitude[8],received,dut.overrun);
 for(i=0;i<16;i=i+1)if(i!=8 && dut.raw_magnitude[i]>dut.raw_magnitude[8]/10)$fatal(1,"I2S leaked into wrong bin%0d",i);
 $display("PASS actual PCM player -> I2S receiver -> spectrum: 48k stereo,1593.75Hz peak at bin8, signed data, no sample overrun");$finish;
end
initial begin #60000000;$fatal(1,"I2S spectrum timeout");end
endmodule
