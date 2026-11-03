`timescale 1ns/1ps
module tb_multi_transition_control;
reg clk=0,rst=1,vs=1,swap=0;reg[1:0] idx=0;reg[5:0] id=0;always #5 clk=~clk;
wire busy,shown;wire[5:0] shownid;wire[1:0] readidx;wire[8:0] progress;wire[3:0] style;
photo_transition #(.MULTI_TRANSITIONS(1)) dut(.clk(clk),.rst(rst),.hs_in(1'b1),.vs_in(vs),.de_in(1'b1),.rgb_in(24'h123456),
 .swap_toggle(swap),.new_idx(idx),.new_photo_id(id),.shown_photo_id(shownid),.shown_toggle(shown),.read_idx(readidx),.busy(busy),
 .hs_out(),.vs_out(),.de_out(),.rgb_out(),.reveal_idx(),.reveal_progress(progress),.reveal_style(style));
task frame;begin @(negedge clk);vs=0;repeat(3)@(negedge clk);vs=1;repeat(8)@(negedge clk);end endtask
integer n,k,expected;reg[8:0] prev;
task commit;input[5:0] photo;input[1:0] buffer;input integer mode;begin
 @(negedge clk);id=photo;idx=buffer;swap=~swap;repeat(5)@(negedge clk);frame;
 if(mode<0)begin frame;if(progress!=0)$fatal(1,"startup animated");end
 else begin
  if(style!==mode)$fatal(1,"wrong style for target %d: %d",photo,style);
  prev=0;
  for(k=1;k<=64;k=k+1)begin
   frame;
   if(progress<prev || progress>256)$fatal(1,"nonmonotonic easing");
   if(mode==0 && progress!==k*4)$fatal(1,"original particle timing changed");
   if(mode!=0 && k==16 && progress!==40)$fatal(1,"missing smoothstep easing");
   prev=progress;
  end
  if(progress!=256)$fatal(1,"incomplete transition");frame;frame;
 end
 if(busy || readidx!==buffer || shownid!==photo)$fatal(1,"commit/hold did not finish");
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;commit(0,0,-1);
 for(n=1;n<=12;n=n+1)commit(n%12,n%2,n-1);
 $display("PASS full 12-photo style sequence, preserved first-pair timing, eased later progress and wrap");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
