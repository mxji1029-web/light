`timescale 1ns/1ps
// Production default path, independently fed through real serial I2S.
// The existing 1024-sample fixture is bin34 at nominal Fs=48kHz:
// 1593.75Hz belongs to contiguous quality band15 (FFT bins29..34).
module tb_spectrum_quality_i2s;
reg audio_clk=0,video_clk=0,rst=1,paused=0,vs=1;
always #40.690 audio_clk=~audio_clk;
always #20 video_clk=~video_clk;
reg [15:0] tone[0:1023];reg [9:0] address=0;
wire [9:0] next_address=address+10'd1;
wire bclk,lrck,dout,pop,tick,av;wire [23:0] left,right;
wire ho,vo,de_out;wire [23:0] rgb_out;
always @(posedge audio_clk)if(rst)address<=0;else if(pop)address<=address+10'd2;
pcm_player_i2s player(.I_mclk(audio_clk),.I_rst(rst),.I_volume(8'd255),.I_pause(paused),
 .I_fifo_dout({tone[next_address],tone[address]}),.I_fifo_empty(1'b0),.O_fifo_re(pop),
 .I_voice_sample(16'sd0),.I_voice_active(1'b0),.O_sample_tick(tick),
 .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(video_clk,rst,bclk,lrck,dout,av,left,right);
// Deliberately no SPECTRUM_QUALITY override: the production default is tested.
audio_waveform_overlay dut(.clk(video_clk),.rst(rst),.hs(1'b1),.vs(vs),.de(1'b0),.rgb(24'h18324c),
 .audio_valid(av),.audio_sample(left[23:8]),.paused(paused),
 .hs_out(ho),.vs_out(vo),.de_out(de_out),.rgb_out(rgb_out));
integer received=0,blocks=0,i,winner,before_pause,blocks_before_pause,nonzero;
reg saw_positive=0,saw_negative=0;
reg [5:0] levels[0:31],peaks[0:31],raw[0:31];
reg [9:0] saved_reference,saved_input_count;
reg [4:0] saved_reference_fraction;
reg [9:0] saved_address;
always @(posedge video_clk)if(!rst)begin
 if(av)begin
  received=received+1;
  if($signed(left[23:8])>1000)saw_positive=1;
  if($signed(left[23:8])< -1000)saw_negative=1;
 end
 if(dut.quality.engine.display_ready)blocks=blocks+1;
 if(dut.quality.engine.overrun)$fatal(1,"quality frontend/FFT/renderer overrun");
end
task frame;begin
 @(negedge video_clk);vs=0;repeat(3)@(negedge video_clk);
 vs=1;repeat(12)@(negedge video_clk);
end endtask
task check_spectrum;begin
 winner=0;nonzero=0;
 for(i=0;i<32;i=i+1)begin
  if(dut.quality.engine.renderer.work_log[i]>dut.quality.engine.renderer.work_log[winner])winner=i;
  if((^dut.quality.engine.renderer.raw_level[i])===1'bx || dut.quality.engine.renderer.raw_level[i]>39)
   $fatal(1,"quality raw band%0d is unknown/out of range",i);
  if(dut.quality.engine.renderer.raw_level[i]!=0)nonzero=nonzero+1;
 end
 if(winner!=15 || nonzero==0 || dut.quality.engine.renderer.raw_level[15]==0)
  $fatal(1,"quality I2S peak: got band%0d nonzero%0d raw15=%0d",winner,nonzero,dut.quality.engine.renderer.raw_level[15]);
 for(i=0;i<32;i=i+1)
  if(dut.quality.engine.renderer.raw_level[i]>dut.quality.engine.renderer.raw_level[15])
   $fatal(1,"quality tone has taller unrelated band%0d",i);
 if(!saw_positive || !saw_negative)$fatal(1,"signed PCM did not survive I2S decoding");
end endtask
initial begin
 $readmemh("../material/spectrum_bars_20261022/tone.hex",tone);
 repeat(5)@(negedge video_clk);rst=0;
 wait(blocks>=2);@(negedge video_clk);check_spectrum;frame;
 if(dut.quality.engine.renderer.display_level[15]==0)$fatal(1,"default32 display never became nonzero");
 paused=1;repeat(8)@(negedge video_clk);
 for(i=0;i<32;i=i+1)begin
  levels[i]=dut.quality.engine.renderer.display_level[i];
  peaks[i]=dut.quality.engine.renderer.display_peak[i];
  raw[i]=dut.quality.engine.renderer.raw_level[i];
 end
 saved_reference=dut.quality.engine.renderer.reference_q4;
 saved_reference_fraction=dut.quality.engine.renderer.reference_fraction;
 saved_input_count=dut.quality.engine.input_count;
 saved_address=address;before_pause=received;blocks_before_pause=blocks;
 wait(received>=before_pause+80);repeat(30)frame;
 if(dut.quality.engine.input_count!==saved_input_count || address!==saved_address)
  $fatal(1,"paused frontend/PCM position advanced");
 if(dut.quality.engine.renderer.reference_q4!==saved_reference ||
    dut.quality.engine.renderer.reference_fraction!==saved_reference_fraction)
  $fatal(1,"paused quality reference moved");
 for(i=0;i<32;i=i+1)
  if(dut.quality.engine.renderer.display_level[i]!==levels[i] ||
     dut.quality.engine.renderer.display_peak[i]!==peaks[i] ||
     dut.quality.engine.renderer.raw_level[i]!==raw[i])
   $fatal(1,"paused quality band/peak/raw moved at band%0d",i);
 if(blocks!=blocks_before_pause)$fatal(1,"paused postprocessor published a block");
 paused=0;wait(blocks>blocks_before_pause);@(negedge video_clk);check_spectrum;frame;
 if(dut.quality.engine.renderer.display_level[15]==0 || dut.quality.engine.overrun)
  $fatal(1,"quality spectrum did not resume cleanly");
 $display("PASS default32 real PCM/I2S: 48k signed tone1593.75Hz strongest band15; 32 raw bands valid, nonzero display, no overrun; bars/peaks/reference/input freeze across80 samples/30 frames then resume");
 $finish;
end
initial begin #120000000;$fatal(1,"quality I2S timeout");end
endmodule
