`timescale 1ns/1ps
module tb_lyric_cdc;
reg ac=0,vc=0,rst=1,vs=1;reg[23:0] ap=0;reg[7:0] al=0;
wire[23:0] p;wire[7:0] l;
always #7 ac=~ac;always #5 vc=~vc;
lyric_state_cdc dut(ac,vc,rst,vs,ap,al,p,l);
always @(posedge ac)if(!rst)begin
 ap<=ap==31?0:ap+1;al<=ap==31?0:(ap+1);
end
reg[23:0] saved;integer i;
initial begin
 #20;rst=0;
 for(i=0;i<20;i=i+1)begin
  @(negedge vc);vs=0;repeat(30)@(negedge vc);
  if(p>31 || l!==p[7:0])$fatal(1,"incoherent mailbox wrap %d %d",p,l);
  vs=1;saved=p;repeat(300)begin @(negedge vc);if(p!==saved)$fatal(1,"active-frame snapshot changed");end
 end
 $display("PASS lyric CDC coherent snapshots across wrap; stable active frame");$finish;
end
endmodule
