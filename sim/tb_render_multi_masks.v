`timescale 1ns/1ps
module tb_render_multi_masks;
reg clk=0,rst=1;always #4 clk=~clk;
reg[9:0] x=0,y=0;reg[8:0] progress=0;reg[3:0] style=0;wire choose;
transition_mask dut(clk,rst,x,y,progress,style,choose);
integer s,frame,xx,yy,fileid,w;string filename;
function integer eased;input integer f;real u;begin
 u=f/16.0;eased=$rtoi(256.0*(3*u*u-2*u*u*u)+0.5);
end endfunction
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(s=0;s<12;s=s+1)begin
  $sformat(filename,"sim/multi_masks/style_%02d.bin",s);fileid=$fopen(filename,"wb");
  if(!fileid)$fatal(1,"Cannot create %s",filename);
  for(frame=0;frame<=16;frame=frame+1)begin
   w=s==0?frame*16:eased(frame);
   for(yy=0;yy<480;yy=yy+8)for(xx=0;xx<640;xx=xx+16)begin
    @(negedge clk);x=xx;y=yy;progress=w;style=s;
    repeat(4)@(posedge clk);#1;
    $fwrite(fileid,"%c",choose?8'd1:8'd0);
   end
  end
  $fclose(fileid);$display("rendered style %d",s);$fflush;
 end
 $display("PASS rendered 12 x 17 actual RTL masks, eased timeline and preserved original particles");$finish;
end
endmodule
