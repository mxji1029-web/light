`timescale 1ns/1ps
module tb_lyric_audio_state;
reg clk=0,rst=1,valid=0;reg signed[15:0] sample=0;
wire[23:0] position;wire[7:0] level;
always #5 clk=~clk;
lyric_audio_state #(.SAMPLES(300)) dut(clk,rst,valid,sample,position,level);
integer i;
initial begin
 #12;rst=0;
 for(i=0;i<256;i=i+1)begin @(negedge clk);valid=1;sample=-32768;end
 @(negedge clk);valid=0;#1;
 if(position!=256 || level!=255)$fatal(1,"counter or absolute minimum amplitude");
 repeat(20)@(negedge clk);
 if(position!=256)$fatal(1,"pause/underrun advanced time");
 for(i=0;i<44;i=i+1)begin @(negedge clk);valid=1;end
 @(negedge clk);valid=0;#1;
 if(position!=0)$fatal(1,"loop did not wrap at exact odd sample count");
 $display("PASS lyric consumed-sample clock, freeze, amplitude and odd loop");$finish;
end
endmodule
