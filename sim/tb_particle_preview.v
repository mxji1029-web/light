`timescale 1ns/1ps
module tb_particle_preview;
reg clk=0,rst=1,req=0;always #4 clk=~clk;
reg[8:0] progress=0;
wire en,ack,done;wire[20:0] addr;
frame_fifo_read #(.PARTICLE_TRANSITION(1),.FRAME_WIDTH(640),.BURST_SIZE(16)) dut(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(en),.App_rd_addr(addr),
 .read_req(req),.read_req_ack(ack),.read_finish(done),.read_addr_0(21'd0),.read_addr_1(21'd307200),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd307200),
 .fifo_aclr(),.wrusedw(10'd0),.reveal_idx(2'd1),.reveal_progress(progress));
reg[23:0] a[0:307199],b[0:307199],px;
integer fileid,count,k,oldcount,newcount;string filename;
always @(posedge clk)if(!rst && en)begin
 if(addr>=307200)begin px=b[addr-307200];newcount=newcount+1;end
 else begin px=a[addr];oldcount=oldcount+1;end
 $fwrite(fileid,"%c%c%c",px[23:16],px[15:8],px[7:0]);count=count+1;
end
initial begin
 $readmemh("sim/particle_preview/photo0.hex",a);$readmemh("sim/particle_preview/photo1.hex",b);
 repeat(5)@(negedge clk);rst=0;
 for(k=0;k<=16;k=k+1)begin
  @(negedge clk);progress=k*16;count=0;oldcount=0;newcount=0;
  $sformat(filename,"sim/particle_preview/frame_%02d.ppm",k);
  fileid=$fopen(filename,"wb");if(!fileid)$fatal(1,"cannot create %s",filename);$fwrite(fileid,"P6\n640 480\n255\n");
  repeat(8)@(negedge clk);req=1;wait(ack);@(negedge clk);req=0;wait(!ack);wait(done);
  @(negedge clk);$fclose(fileid);
  if(count!=307200)$fatal(1,"short frame");
  if(k>0 && k<16 && (!oldcount || !newcount))$fatal(1,"solid intermediate");
  $display("frame %d: old=%d new=%d",k,oldcount,newcount);$fflush;
  repeat(5)@(negedge clk);
 end
 $display("PASS: 17 full-resolution frames from actual read addresses; no intermediate background");$finish;
end
endmodule

