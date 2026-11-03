`timescale 1ns/1ps
// Frozen optimization oracle ignores global busy/ref. Keep those flags quiet
// here; tb_sdram_start_guard and real-controller phase78 score new stalls.
module tb_write_fifo_equivalence #(parameter integer BURST=128,ADDR=21);
reg clk=0,rst=1,request=0,rd_busy=0,init=0,refresh=0,mem_busy=0;
always #4 clk=~clk;
reg[ADDR-1:0] length=0;reg[9:0] occupancy=0;
wire we,ack,finish,clear,busy;wire[ADDR-1:0] address;
wire ref_we,ref_ack,ref_finish,ref_clear,ref_busy;wire[ADDR-1:0] ref_address;
frame_fifo_write #(.ADDR_BITS(ADDR),.BURST_BITS(10),.BURST_SIZE(BURST)) dut(
 rst,clk,init,refresh,mem_busy,rd_busy,busy,we,address,request,ack,finish,
 ADDR'(0),ADDR'(307200),ADDR'(614400),ADDR'(921600),2'd1,length,clear,occupancy);
frame_fifo_write_before_opt #(.ADDR_BITS(ADDR),.BURST_BITS(10),.BURST_SIZE(BURST)) reference(
 rst,clk,init,refresh,mem_busy,rd_busy,ref_busy,ref_we,ref_address,request,ref_ack,ref_finish,
 ADDR'(0),ADDR'(307200),ADDR'(614400),ADDR'(921600),2'd1,length,ref_clear,occupancy);
integer cycle=0,checked=0,j,k,writes,seed=90127,add;
always @(negedge clk)begin
 cycle=cycle+1;
 rd_busy=(cycle%23>=19);refresh=0;mem_busy=0;
 if(rst || clear)occupancy=0;
 else begin
  add=($random(seed)&3);if(cycle%17==0)add=0;
  if(we && occupancy>0)occupancy=occupancy-1;
  if(occupancy+add<=510)occupancy=occupancy+add;
 end
end
always @(posedge clk)begin
 #1;
 if(!rst)begin
  if({we,ack,finish,clear,busy,address}!=={ref_we,ref_ack,ref_finish,ref_clear,ref_busy,ref_address})
   $fatal(1,"write FIFO diverged burst%0d cycle%0d state%0d left%0d occupancy%0d",BURST,cycle,dut.state,dut.write_left,occupancy);
  checked=checked+1;
 end
end
task run;input integer size;begin
 @(negedge clk);rst=1;request=0;repeat(4)@(negedge clk);rst=0;
 @(negedge clk);length=size;request=1;wait(ack);repeat(3)@(negedge clk);request=0;
 if(size%BURST==0)begin wait(finish);repeat(4)@(negedge clk);end
 else begin
  // Frozen controller supports complete bursts only. Partial tails stall in
  // BOTH versions: compare a bounded window, then reset before the next case.
  repeat(size+BURST*6+200)@(negedge clk);
  if(finish || ref_finish)$fatal(1,"unexpected partial-tail semantics change");
 end
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;init=1;
 run(1);run(BURST-1);run(BURST);run(BURST+1);
 if(ADDR>=12)begin run(4*BURST+7);run(1041);end
 if(ADDR==21)run(307200);
 else begin run((1<<ADDR)-1);run((1<<ADDR)-BURST);end
 $display("PASS FIFO cycle equivalence: burst%0d/address%0d,%0d exact cycles; complete bursts,bounded legacy partial stalls,arbitration/wrap",BURST,ADDR,checked);$finish;
end
initial begin #50000000;$fatal(1,"FIFO equivalence timeout");end
endmodule
