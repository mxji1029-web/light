`timescale 1ns/1ps
// Production top integration: PLLs, SDRAM and the encrypted HDMI core are
// omitted with -i. Clock/card inputs are forced; all transport/lyric/transition
// controls remain the actual production instances and wiring.
module tb_top_playback_pause;
reg clk=0,video_clk=0,audio_clk=0,sd_clk=0,rst_n=0,key3=1;
always #10 clk=~clk;
always #20 video_clk=~video_clk;
always #41 audio_clk=~audio_clk;
always #5 sd_clk=~sd_clk;
top dut(.clk(clk),.rst_n(rst_n),.key1(1'b1),.key2(1'b1),.key3(key3),.sd_miso(1'b1));
defparam dut.u_picture_controls.CLK_HZ=1000;
defparam dut.u_picture_controls.DEBOUNCE_MS=2;
defparam dut.u_picture_controls.HOLD_MS=20;
defparam dut.u_photo_transition.FADE_FRAMES=4;
reg vs=1,swap=0;reg[1:0] bufidx=0;reg[5:0] photo=0;
reg[31:0] pair_index=0;wire[15:0] lo=pair_index*2+1,hi=pair_index*2+2;
wire[31:0] fifo_data={hi,lo};
integer consumed=0,expected=1,ticks=0;
always @(posedge audio_clk)if(rst_n)begin
 if(dut.pcm_fifo_re)pair_index<=pair_index+1;
 if(dut.bgm_consumed)begin
  if(dut.bgm_sample!==expected)$fatal(1,"resume skipped/repeated PCM sample: got %d expected %d",dut.bgm_sample,expected);
  expected=expected+1;consumed=consumed+1;
 end
 if(dut.audio_sample_tick)ticks=ticks+1;
end
task wait_video;input integer n;begin repeat(n)@(negedge video_clk);end endtask
task frame;begin vs=0;wait_video(3);vs=1;wait_video(10);end endtask
task tap;begin key3=0;wait_video(8);key3=1;wait_video(10);end endtask
integer pos_saved,pops_saved,progress_saved,ticks_saved,i;
initial begin
 force dut.video_clk=video_clk;force dut.audio_mclk=audio_clk;
 force dut.sd_card_clk=sd_clk;force dut.audio_pll_lock=1'b1;
 force dut.pcm_fifo_empty=1'b0;force dut.pcm_fifo_dout=fifo_data;
 force dut.pcm_found=1'b1;
 force dut.vs=vs;force dut.hs=1'b1;force dut.de=1'b0;force dut.vout_data_raw=24'h4488cc;
 force dut.disp_commit_toggle=swap;force dut.disp_buf_idx=bufidx;force dut.photo_index=photo;
 wait_video(5);rst_n=1;wait_video(5);
 swap=1;wait_video(5);repeat(3)frame;
 repeat(600)@(negedge audio_clk);
 if(!dut.image_seen_audio[1] || !dut.playback_paused || consumed!=0 || pair_index!=0)
  $fatal(1,"boot must display first photo without consuming audio");
 if(dut.audio_code!=2)$fatal(1,"paused status missing");
 tap();wait(consumed>=5);@(negedge video_clk);
 if(dut.playback_paused || dut.audio_code!=1)$fatal(1,"KEY3 first short release did not start");
 tap();repeat(10)@(negedge audio_clk);
 pos_saved=dut.lyric_audio_position;pops_saved=pair_index;ticks_saved=ticks;
 repeat(1400)@(negedge audio_clk);
 if(dut.lyric_audio_position!=pos_saved || pair_index!=pops_saved || !dut.audio_pause)
  $fatal(1,"pause advanced PCM/lyric position");
 if(ticks<=ticks_saved)$fatal(1,"pause stopped I2S clocks");
 // A manual photo request may be buffered while paused, but its dissolve
 // stays at the same frame until playback resumes.
 bufidx=1;photo=1;swap=0;wait_video(8);frame;
 repeat(6)frame;
 if(!dut.transition_busy || dut.reveal_progress!=0 || dut.read_buf_idx!=0)
  $fatal(1,"paused manual transition advanced");
 // Long press enters/exits settings without changing paused transport.
 key3=0;wait_video(35);key3=1;wait_video(10);
 if(!dut.settings_active || !dut.playback_paused)$fatal(1,"long press toggled playback");
 tap();if(!dut.settings_selected || !dut.playback_paused)$fatal(1,"settings short release toggled playback");
 key3=0;wait_video(35);key3=1;wait_video(10);
 if(dut.settings_active || !dut.playback_paused)$fatal(1,"settings exit toggled playback");
 tap();frame;frame;
 if(dut.reveal_progress==0)$fatal(1,"resume did not advance transition");
 progress_saved=dut.reveal_progress;
 tap();repeat(10)frame;
 if(dut.reveal_progress!=progress_saved)$fatal(1,"mid-transition pause did not freeze phase");
 pos_saved=dut.lyric_audio_position;repeat(1000)@(negedge audio_clk);
 if(dut.lyric_audio_position!=pos_saved)$fatal(1,"second pause advanced lyrics");
 tap();repeat(8)frame;wait(consumed>=10);#1;
 if(dut.transition_busy || dut.read_buf_idx!=1)$fatal(1,"resume failed to finish transition");
 if(dut.lyric_audio_position!=consumed)$fatal(1,"lyric clock differs from consumed samples");
 $display("PASS production top playback: boot pause, KEY3 start/pause/resume, contiguous PCM, frozen lyrics and dissolve, live I2S, preserved settings");$finish;
end
initial begin #3000000;$fatal(1,"top playback timeout");end
endmodule
