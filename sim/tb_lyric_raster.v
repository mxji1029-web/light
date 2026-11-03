`timescale 1ns/1ps
// Six complete rendered frames, independently checked by check_lyric_raster.py.
module tb_lyric_raster;
reg clk=0,rst=1,vs=1,de=0;reg[23:0] position=0;
wire ho,vo,dout;wire[23:0] rgb;
always #5 clk=~clk;
lyric_overlay dut(clk,rst,1'b1,vs,de,24'd0,position,8'd200,ho,vo,dout,rgb);
integer f,x,y,k,age;reg capture=0;
always @(posedge clk)begin
 #1;if(capture && dout)$fwrite(f,"%c",(rgb==24'hf5c784 || rgb==24'hf6ecd4)?8'd1:8'd0);
end
initial begin
 #12;rst=0;f=$fopen("lyric_raster.bin","wb");
 for(k=0;k<6;k=k+1)begin
  case(k)0:age=0;1:age=4096;2:age=7168;3:age=8192;4:age=12288;5:age=13312;endcase
  position=24'd1371408+age;
  @(negedge clk);vs=0;repeat(20)@(negedge clk);vs=1;repeat(240)@(negedge clk);
  capture=1;
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)begin de=1;@(negedge clk);end
   de=0;repeat(8)@(negedge clk);
  end
  repeat(4)@(negedge clk);capture=0;
 end
 $fclose(f);$display("PASS six caption raster frames captured");$finish;
end
endmodule
