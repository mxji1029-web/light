`timescale 1ns/1ps
// Real production controls, volume mailbox/ramp, PCM/I2S and metadata CDC.
// Only clocks, card/FIFO status and raw video are isolated from hard IP.
module tb_top_volume_status;
reg clk=0,vc=0,ac=0,sc=0,rst_n=0,kn=1,ka=1,kp=1,vs=1,swap=0;
always #10 clk=~clk;always #20 vc=~vc;always #41 ac=~ac;always #5 sc=~sc;
top dut(.clk(clk),.rst_n(rst_n),.key1(kn),.key2(ka),.key3(kp),.sd_miso(1'b1));
defparam dut.u_picture_controls.CLK_HZ=1000;
defparam dut.u_picture_controls.DEBOUNCE_MS=2;
defparam dut.u_picture_controls.HOLD_MS=20;
integer consumed=0,ticks_seen=0,received=0,guard,i,at_mute;
always @(posedge ac)if(rst_n)begin
 if(dut.bgm_consumed)consumed=consumed+1;
 if(dut.audio_sample_tick)ticks_seen=ticks_seen+1;
end
always @(posedge vc)if(rst_n && dut.audio_valid)received=received+1;
task ticks;input integer n;begin repeat(n)@(negedge vc);end endtask
task frame;begin vs=0;ticks(12);vs=1;ticks(20);end endtask
task tap;input integer key;begin
 if(key==0)kn=0;else if(key==1)ka=0;else kp=0;
 ticks(8);kn=1;ka=1;kp=1;ticks(8);
end endtask
task long_key3;begin kp=0;ticks(35);kp=1;ticks(10);end endtask
task wait_gain;input integer wanted;begin
 guard=0;while(dut.audio_volume_gain!==wanted && guard<400000)begin @(negedge ac);guard=guard+1;end
 if(dut.audio_volume_gain!==wanted)$fatal(1,"audio gain did not converge to%0d",wanted);
end endtask
task check_received;input[23:0] wanted;integer count;begin
 count=0;guard=0;
 while(count<3 && guard<20000)begin
  @(negedge vc);guard=guard+1;
  if(dut.audio_valid)begin
   if(dut.audio_left_data!==wanted || dut.audio_right_data!==wanted)count=0;else count=count+1;
  end
 end
 if(count<3)$fatal(1,"I2S decoded output did not settle to%h left%h",wanted,dut.audio_left_data);
end endtask
initial begin
 force dut.video_clk=vc;force dut.audio_mclk=ac;force dut.sd_card_clk=sc;
 force dut.audio_pll_lock=1'b1;force dut.pcm_fifo_empty=1'b0;
 force dut.pcm_fifo_dout=32'h2ee02ee0;force dut.pcm_found=1'b1;
 force dut.hs=1'b1;force dut.vs=vs;force dut.de=1'b0;force dut.vout_data_raw=24'h4488cc;
 force dut.display_valid=1'b1;force dut.disp_commit_toggle=swap;
 force dut.disp_buf_idx=2'd0;force dut.photo_index=6'd0;
 force dut.album_photo_count_sd=7'd22;force dut.album_auto_play_sd=1'b0;
 ticks(5);rst_n=1;ticks(5);swap=1;ticks(5);repeat(6)frame;
 if(!dut.playback_paused || consumed!=0 || dut.settings_volume_level!=10 || dut.audio_volume_gain!=255)$fatal(1,"boot defaults changed");
 if(dut.album_status_video!==8'd22)$fatal(1,"actual SD metadata CDC did not snapshot22");
 tap(2);wait(consumed>5);check_received(24'h230400);
 long_key3;tap(2);tap(2);
 if(!dut.settings_active || dut.settings_selected!=2 || dut.playback_paused)$fatal(1,"volume page changed transport");
 repeat(10)tap(0);frame;
 if(dut.settings_volume_level!=0 || dut.settings_volume_frame!=0 || dut.settings_brightness!=0 || dut.settings_contrast!=2)$fatal(1,"volume controls leaked into photo parameters");
 wait_gain(0);check_received(0);at_mute=consumed;
 repeat(2048)@(negedge ac);
 if(consumed<=at_mute || dut.playback_paused)$fatal(1,"mute paused/skipped the source clock");
 repeat(10)tap(1);frame;wait_gain(255);check_received(24'h230400);
 long_key3;if(dut.settings_active || dut.playback_paused)$fatal(1,"menu exit paused playback");
 tap(2);repeat(1024)@(negedge ac);at_mute=consumed;check_received(0);
 repeat(2048)@(negedge ac);
 if(consumed!=at_mute || !dut.playback_paused)$fatal(1,"global pause did not freeze PCM");
 tap(2);check_received(24'h230400);
 if(ticks_seen<2000 || received<10)$fatal(1,"insufficient actual serial output coverage");
 $display("PASS production top volume: menu0/100, coherent metadata22, real I2S identity/mute/unmute, mute keeps source running, KEY3 pause/resume preserved; samples%0d",consumed);$finish;
end
initial begin #120000000;$fatal(1,"top volume timeout");end
endmodule
