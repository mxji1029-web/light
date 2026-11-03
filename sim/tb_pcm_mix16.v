`timescale 1ns/1ps
module tb_pcm_mix16;
  reg signed [15:0] bgm,voice;
  reg [7:0] bg,vg;
  wire signed [15:0] mixed;
  pcm_mix16 dut(.bgm(bgm),.voice(voice),.bgm_gain(bg),.voice_gain(vg),.mixed(mixed));
  task check;
    input signed [15:0] b,v;
    input [7:0] g,h;
    input signed [15:0] expected;
    begin
      bgm=b;voice=v;bg=g;vg=h;#1;
      if(mixed!==expected) $fatal(1,"mix %d %d -> %d expected %d",b,v,mixed,expected);
    end
  endtask
  initial begin
    check(1000,2000,128,128,1500);
    check(-1000,-2000,128,128,-1500);
    check(32767,32767,255,255,32767);
    check(-32768,-32768,255,255,-32768);
    check(-32768,32767,128,128,-1);
    check(12345,-23456,0,0,0);
    check(1000,1000,64,192,1000);
    $display("PASS: signed mixing, ducking gains, positive/negative saturation");$finish;
  end
endmodule
