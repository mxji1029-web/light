`timescale 1ns/1ps
module tb_transition_masks;
reg clk=0,rst=1;always #4 clk=~clk;
reg[9:0] x=0,y=0;reg[8:0] progress=0;reg[3:0] style=0;wire choose;
transition_mask dut(clk,rst,x,y,progress,style,choose);
reg[2399:0] previous,current,signatures[0:11];
integer s,p,xx,yy,i,j,new_count;
function integer original_noise;input integer px,py;reg[15:0] a,b,t;reg[7:0] h;
begin a=(px>>4)*40503;b=(py>>3)*34283;t=a^b;h=t[7:0]^t[15:8];original_noise=h^(h>>3);end
endfunction
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(s=0;s<12;s=s+1)begin
  previous=0;
  for(p=0;p<=256;p=p+16)begin
   i=0;new_count=0;
   for(yy=0;yy<480;yy=yy+8)for(xx=0;xx<640;xx=xx+16)begin
    @(negedge clk);x=xx;y=yy;progress=p;style=s;
    repeat(4)@(posedge clk);#1;
    if(choose!==0 && choose!==1)$fatal(1,"unknown mask output");
    if(p==0 && choose)$fatal(1,"old endpoint violated style=%d",s);
    if(p==256 && !choose)$fatal(1,"new endpoint violated style=%d",s);
    if(s==0 && choose!==((p==256)||(original_noise(xx,yy)<p)))$fatal(1,"first-pair particles changed");
    current[i]=choose;if(choose)new_count=new_count+1;i=i+1;
   end
   if((previous & ~current)!=0)$fatal(1,"reappearing particle/edge style=%d progress=%d",s,p);
   if(p==128)begin
    if(new_count==0 || new_count==2400)$fatal(1,"solid intermediate style=%d",s);
    signatures[s]=current;$display("style %d midpoint: %d/2400 new cells",s,new_count);
   end
   previous=current;
  end
 end
 for(i=0;i<12;i=i+1)for(j=0;j<i;j=j+1)
  if(signatures[i]===signatures[j])$fatal(1,"duplicate transition geometry %d %d",i,j);
 $display("PASS 12 distinct geometries, 17 progress steps, exact original particles, monotonicity and both endpoints");$finish;
end
endmodule
