`timescale 1ns/1ps
// Official APUG011 launch contract on the actual frame controllers.
// busy includes an active transfer: block NEW bursts, never gate their beats.
module tb_sdram_start_guard;
reg clk=0,rst=1,busy=0,refresh=0,rreq=0,wreq=0;
always #4 clk=~clk;
wire ren,wen,rack,wack,rdone,wdone;
wire[20:0] ra,wa;
integer reads=0,writes=0,phase=0,errors=0,k,guard;
frame_fifo_read #(.BURST_SIZE(16)) r(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_busy(busy),.Sdr_init_ref_vld(refresh),
 .Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.App_rd_en(ren),.App_rd_addr(ra),
 .reveal_style(4'd0),.reveal_idx(2'd0),.reveal_progress(9'd0),
 .read_req(rreq),.read_req_ack(rack),.read_finish(rdone),
 .read_addr_0(21'd0),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(2'd0),.read_len(21'd16),.wrusedw(10'd0));
frame_fifo_write #(.BURST_SIZE(128)) w(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_busy(busy),.Sdr_init_ref_vld(refresh),
 .App_rd_busy(1'b0),.App_wr_en(wen),.App_wr_addr(wa),
 .write_req(wreq),.write_req_ack(wack),.write_finish(wdone),
 .write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd0),.write_len(21'd128),.rdusedw(10'd256));
always @(posedge clk)if(!rst)begin
 if(ren)reads=reads+1;
 if(wen)writes=writes+1;
 if(phase>=1 && phase<=3 && (ren||wen))begin
  if(errors<4)$display("UNSAFE_LAUNCH phase=%0d busy=%b refresh=%b read=%b write=%b",phase,busy,refresh,ren,wen);
  errors=errors+1;
 end
end
task reset_case;begin
 @(negedge clk);phase=0;rst=1;rreq=0;wreq=0;busy=0;refresh=0;
 repeat(4)@(negedge clk);reads=0;writes=0;rst=0;
end endtask
task request;begin
 rreq=1;wreq=1;guard=0;
 while((!rack||!wack)&&guard<30)begin @(negedge clk);guard=guard+1;end
 if(!rack||!wack)$fatal(1,"request ACK missing");
 rreq=0;wreq=0;
end endtask
task finish_case;begin
 guard=0;while((reads<16 || writes<128)&&guard<400)begin @(negedge clk);guard=guard+1;end
 repeat(30)@(negedge clk);
 if(reads!=16 || writes!=128)$fatal(1,"beat count changed read=%0d write=%0d",reads,writes);
end endtask
initial begin
 for(k=1;k<=3;k=k+1)begin
  reset_case;phase=k;busy=k!=2;refresh=k!=1;request;
  repeat(40)@(negedge clk);
  if(reads || writes)begin $display("FAIL controller started while official busy/refresh contract prohibits it");end
  phase=0;busy=0;refresh=0;finish_case;
 end
 // busy may assert because this controller's own accepted burst is active.
 // It must finish without withholding any of the in-flight beats.
 reset_case;phase=4;request;wait(ren||wen);@(negedge clk);busy=1;
 repeat(180)@(negedge clk);busy=0;finish_case;
 if(errors)$fatal(1,"APUG011 launch contract violated on%0d beats",errors);
 $display("PASS APUG011 busy/ref launch guard; delayed release;16 reads/128 writes; own-busy does not stall accepted bursts");$finish;
end
initial begin #50000;$fatal(1,"launch guard timeout");end
endmodule
