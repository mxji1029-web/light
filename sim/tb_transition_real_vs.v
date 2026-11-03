`timescale 1ns/1ps
module tb_transition_real_vs;
reg clk=0,rst=1;always #5 clk=~clk;
wire hs,vs,de;reg swap=0;reg[1:0] idx=0;reg[5:0] id=0;
wire busy,shown;wire[5:0] shownid;wire[1:0] rid,target;wire[8:0] progress;
wire ho,vo,deo;wire[23:0] rgb;
color_bar #(.H_ACTIVE(64),.H_FP(4),.H_SYNC(8),.H_BP(8),
 .V_ACTIVE(48),.V_FP(2),.V_SYNC(2),.V_BP(3)) timing(
 .clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_r(),.rgb_g(),.rgb_b());
photo_transition #(.FADE_FRAMES(8)) dut(.clk(clk),.rst(rst),.hs_in(hs),.vs_in(vs),.de_in(de),
 .rgb_in(24'h123456),.swap_toggle(swap),.new_idx(idx),.new_photo_id(id),
 .shown_photo_id(shownid),.shown_toggle(shown),.read_idx(rid),.busy(busy),
 .hs_out(ho),.vs_out(vo),.de_out(deo),.rgb_out(rgb),.reveal_idx(target),.reveal_progress(progress));
reg vs_d=1;reg[8:0] prev=0;reg[1:0] prev_idx=0;
integer changes=0,frames=0;reg edge_now;
always @(posedge clk)begin
 edge_now=vs_d && !vs;vs_d=vs;
 #1;
 if(!rst)begin
  if(progress!=prev || rid!=prev_idx)begin
   if(!edge_now)$fatal(1,"control changed outside frame boundary");
   if(progress!=0 && progress!=256)changes=changes+1;
  end
  if({ho,vo,deo}!=={hs,vs,de})$fatal(1,"video latency changed");
  if(de && (vs!==1 || rgb!==24'h123456))$fatal(1,"active video polarity or solid backdrop regression");
  if(edge_now)frames=frames+1;
 end
 prev=progress;prev_idx=rid;
end
 task commit;input[5:0] photo;input[1:0] buffer;begin
 @(negedge clk);id=photo;idx=buffer;swap=~swap;
 wait(busy);wait(!busy);@(negedge clk);
 if(shownid!==photo || rid!==buffer)$fatal(1,"wrong committed picture");
end endtask
integer before_changes;
initial begin
 repeat(5)@(negedge clk);rst=0;
 commit(0,0);if(changes!=0)$fatal(1,"startup must not dissolve");
 commit(1,1);if(changes!=7)$fatal(1,"first 0->1 did not animate: %d",changes);
 before_changes=changes;
 commit(2,0);commit(0,1);commit(1,0);
 if(changes!=before_changes)$fatal(1,"later switch repeated special effect");
 $display("PASS real low-active VS, first pair only, monotonic progress, no backdrop, later hard cuts");$finish;
end
initial begin #3000000;$fatal(1,"timeout");end
endmodule
