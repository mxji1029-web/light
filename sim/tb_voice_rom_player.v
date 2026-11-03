`timescale 1ns/1ps
module tb_voice_rom_player;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1,toggle=0,tick=0,pause=0;
  reg [5:0] id=0;
  wire signed [15:0] pcm;
  wire active;
  voice_rom_player #(.SLOT_BITS(2),.LENGTH0(4),.LENGTH1(4),.LENGTH2(4),.LENGTH3(4),
    .ROM_FILE("D:/FPGA/competition/03_dev/oral_album_lyrics28/sim/test_voice.hex")) dut(
    .clk(clk),.rst(rst),.photo_id(id),.photo_toggle(toggle),
    .sample_tick(tick),.pause(pause),.sample(pcm),.active(active));
  task trigger;
    input [5:0] target;
    begin @(negedge clk);id=target;toggle=~toggle;repeat(10) @(negedge clk);end
  endtask
  task consume;
    input [15:0] expected;
    integer n;
    begin
      for(n=0;n<6;n=n+1)begin
        if(pcm!==expected || !active)$fatal(1,"voice %h expected %h, active=%b",pcm,expected,active);
        tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);
      end
    end
  endtask
  task trigger_delayed_id;
    input [5:0] target;
    begin
      // Model one data bit/bus capture arriving a destination cycle after toggle.
      @(negedge clk);toggle=~toggle;
      @(negedge clk);id=target;
      repeat(10)@(negedge clk);
    end
  endtask
  initial begin
    repeat(4)@(negedge clk);rst=0;
    trigger(0);consume(16'h1000);
    pause=1;repeat(12)begin tick=1;@(negedge clk);tick=0;@(negedge clk);end
    if(pcm!==16'h2000)$fatal(1,"pause advanced voice position");
    pause=0;consume(16'h2000);
    trigger(2);consume(16'h8000); // negative signed sample, restart while active
    trigger(3);consume(16'hc000);consume(16'hd000);consume(16'he000);consume(16'hf000);
    if(active || pcm!==0)$fatal(1,"voice did not stop at exact end");
    trigger(1);consume(16'h5000);
    trigger_delayed_id(2);consume(16'h8000);
    trigger(4);if(active || pcm!==0)$fatal(1,"missing photo4 voice aliased to photo0");
    trigger(63);if(active || pcm!==0)$fatal(1,"missing photo63 voice aliased to photo3");
    $display("PASS: photo selection, signed ROM, 6x hold, pause, restart, EOF");$finish;
  end
  initial begin #100000;$fatal(1,"timeout");end
endmodule
