`timescale 1ns/1ps
module tb_lyric_overlay;
reg clk=0,rst=1,hs=1,vs=1,de=0;reg[23:0] rgb=24'hb08060;
reg[23:0] position=0;reg[7:0] level=200;
wire ho,vo,dout;wire[23:0] out;
always #5 clk=~clk;
lyric_overlay dut(clk,rst,hs,vs,de,rgb,position,level,ho,vo,dout,out);
reg[2:0] s0=0,s1=0;reg[23:0] r0=0,r1=0;
integer x,y,f,drawn=0;reg write_frame=0;
always @(posedge clk)begin
 if(rst)begin s0=0;s1=0;r0=0;r1=0;end
 else begin s1=s0;s0={hs,vs,de};r1=r0;r0=rgb;end
 #1;
 if({ho,vo,dout}!==s1)$fatal(1,"RGB/VS/HS/DE pipeline is not two cycles");
 if(!rst && dout && dut.y0<300 && out!==r1)$fatal(1,"photo pixels changed above caption band");
 if(write_frame && dout)begin
  $fwrite(f,"%c%c%c",out[23:16],out[15:8],out[7:0]);
  if(out==24'hf5c784 || out==24'hf6ecd4)drawn=drawn+1;
 end
end
// The sentence window is resolved once per frame by the table scan, so every
// check pulses vs and waits for the 64-entry scan (3 clocks each) to finish.
task check_line;input[23:0] t;input[8:0] b;input valid;begin
 position=t;
 vs=0;repeat(4)@(negedge clk);vs=1;
 repeat(240)@(negedge clk);
 if(dut.line_valid!==valid || (valid && dut.line_base!==b))$fatal(1,"sentence boundary %d",t);
end endtask
initial begin
 #12;rst=0;
 check_line(24'd1234567,9'd0,1'b0);          // after the title cards, before the first lyric
 check_line(24'd72000,9'd0,1'b1);            // "我记得" title card
 check_line(24'd240000,9'd3,1'b1);           // "赵雷"
 check_line(24'd1371408,9'd5,1'b1);          // first sung line
 // New sentence wins immediately, even when the previous one has a 300 ms tail.
 check_line(24'd1501920,9'd15,1'b1);
 position=24'd1400000;
 f=$fopen("lyric_frame.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");
 @(negedge clk);vs=0;repeat(20)@(negedge clk);vs=1;repeat(240)@(negedge clk);
 write_frame=1;
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)begin de=1;@(negedge clk);end
  de=0;repeat(8)@(negedge clk);
 end
 repeat(4)@(negedge clk);write_frame=0;$fclose(f);
 if(drawn<50)$fatal(1,"glyph ROM produced no visible captions");
 $display("PASS lyric sentence table, two-cycle video alignment, visible brush glyphs: %d pixels",drawn);$finish;
end
endmodule
