`timescale 1ns/1ps
module tb_pcm_player_i2s;
  reg clk=0;
  always #40.667 clk=~clk; // actual approximately 12.295MHz audio domain
  reg video_clk=0;
  always #20 video_clk=~video_clk;
  reg rst=1,pause=0,voice_active=0;
  reg signed[15:0] voice=1000;
  wire bclk,lrck,dout,pop,tick;
  integer pair_index=0,next_sample=1,frame_ticks=0;
  wire[15:0] low=(pair_index*2+1)*100;
  wire[15:0] high=(pair_index*2+2)*100;
  wire[31:0] fifo={high,low};
  pcm_player_i2s dut(.I_mclk(clk),.I_rst(rst),.I_volume(8'd255),.I_pause(pause),
    .I_fifo_dout(fifo),.I_fifo_empty(1'b0),.O_fifo_re(pop),
    .I_voice_sample(voice),.I_voice_active(voice_active),.O_sample_tick(tick),
    .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
  wire received_valid;
  wire [23:0] received_left,received_right;
  integer received_frames=0;
  I2S_receiver receiver(.I_clk(video_clk),.I_rst(rst),.I_i2s_BCLK(bclk),
    .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(received_valid),
    .O_audio_left_data(received_left),.O_audio_right_data(received_right));
  always @(posedge video_clk) if(!rst && received_valid)begin
    if(received_frames>1 && received_left!==received_right)
      $fatal(1,"actual downstream receiver stereo mismatch %h %h",received_left,received_right);
    received_frames=received_frames+1;
  end
  integer expected=0,raw_mix;
  always @(posedge clk)begin
    if(rst)begin pair_index<=0;next_sample=1;expected=0;frame_ticks=0;end
    else begin
      if(pop) pair_index<=pair_index+1;
      if(tick)begin
        frame_ticks=frame_ticks+1;
        if(pause) expected=0;
        else begin
          raw_mix=voice_active ? ((next_sample*100*64+1000*192)>>>8)
                               : ((next_sample*100*192)>>>8);
          expected=(raw_mix*255)>>>8;
          next_sample=next_sample+1;
        end
      end
    end
  end
  reg[23:0] left,right;
  integer k,frame_expected;
  task check_frame;
    begin
      @(negedge lrck);#1;frame_expected=expected;
      @(posedge bclk); // Philips I2S: one bit clock after LRCK changes
      left=0;
      for(k=0;k<24;k=k+1)begin @(posedge bclk);#1;left={left[22:0],dout};end
      @(posedge lrck);@(posedge bclk);right=0;
      for(k=0;k<24;k=k+1)begin @(posedge bclk);#1;right={right[22:0],dout};end
      if(left!==right)$fatal(1,"left/right mismatch %h %h",left,right);
      if($signed(left)!==frame_expected*256)$fatal(1,"mixed sample %d expected %d",$signed(left),frame_expected*256);
    end
  endtask
  initial begin
    repeat(4)@(negedge clk);rst=0;
    repeat(4)check_frame;
    @(negedge clk);voice_active=1;repeat(4)check_frame;
    @(negedge clk);pause=1;repeat(3)check_frame;
    @(negedge clk);pause=0;voice_active=0;repeat(3)check_frame;
    if(frame_ticks<14)$fatal(1,"missing sample ticks");
    if(received_frames<10)$fatal(1,"actual downstream receiver did not decode enough frames");
    $display("PASS: decoded I2S stereo, continuous BGM samples, voice mix, pause/resume");$finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
