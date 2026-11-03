`timescale 1ns/1ps
// Exercise the real top-level image-valid gate with hard IP omitted by -i.
module tb_display_ready_frame;
reg clk=0,video_clk=0,rst_n=0,ready=0,vs=1;
always #10 clk=~clk;
always #20 video_clk=~video_clk;
top dut(.clk(clk),.rst_n(rst_n),.key1(1'b1),.key2(1'b1),.key3(1'b1),.sd_miso(1'b1));
task ticks;input integer n;begin repeat(n)@(negedge video_clk);end endtask
task expect_rgb;input[23:0] wanted;begin
 #1;if(dut.vout_data!==wanted)$fatal(1,"display enable must change only in blanking: got %h want %h",dut.vout_data,wanted);
end endtask
initial begin
 force dut.video_clk=video_clk;
 force dut.audio_pll_lock=1'b1;
 force dut.display_valid=ready;
 force dut.vs_t=vs;
 force dut.vout_data_faded=24'hc18357;
 ticks(4);rst_n=1;ticks(5);expect_rgb(0);
 // Asynchronous source changes in active video must not expose a partial frame.
 #7;ready=1;#1;expect_rgb(0);
 ticks(8);expect_rgb(0);
 vs=0;ticks(6);vs=1;expect_rgb(24'hc18357);
 ticks(9);#7;ready=0;#1;expect_rgb(24'hc18357);
 ticks(8);expect_rgb(24'hc18357);
 vs=0;ticks(6);vs=1;expect_rgb(0);
 // A short source excursion completely between frames must not blank a frame.
 ready=1;ticks(6);vs=0;ticks(6);vs=1;expect_rgb(24'hc18357);
 ready=0;ticks(4);ready=1;ticks(4);expect_rgb(24'hc18357);
 // Reset is the one allowed immediate blanking event.
 rst_n=0;#1;expect_rgb(0);
 $display("PASS production display-ready CDC: asynchronous enable/disable, whole-frame gate, transient and reset");
 $finish;
end
initial begin #200000;$fatal(1,"display-ready timeout");end
endmodule
