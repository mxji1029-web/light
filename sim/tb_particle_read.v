`timescale 1ns/1ps
module tb_particle_read;
reg clk=0,rst=1,req=0;always #4 clk=~clk;
reg[1:0] idx=0,target=1;reg[8:0] progress=0;
wire en,ack,done,clear,busy;wire[20:0] addr;
localparam W=64,H=48,N=W*H,A=0,B=307200;
frame_fifo_read #(.PARTICLE_TRANSITION(1),.FRAME_WIDTH(W),.BURST_SIZE(16)) dut(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(busy),.App_rd_en(en),.App_rd_addr(addr),
 .read_req(req),.read_req_ack(ack),.read_finish(done),.read_addr_0(21'd0),.read_addr_1(21'd307200),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(idx),.read_len(21'd3072),
 .fifo_aclr(clear),.wrusedw(10'd0),.reveal_idx(target),.reveal_progress(progress));
integer count=0,old_count,new_count,expect_base,frame_w=0,old_base,new_base;
reg [N-1:0] prior=0,current;
reg [20:0] last_addr;reg last_en=0;
function integer threshold;input integer offset;reg[15:0] a,b,t;reg[7:0] h;
begin a=((offset%W)>>4)*40503;b=((offset/W)>>3)*34283;t=a^b;h=t[7:0]^t[15:8];threshold=h^(h>>3);end
endfunction
always @(posedge clk)if(!rst)begin
 if(en)begin
  if(count>=N)$fatal(1,"too many read requests");
  expect_base=(frame_w==256 || threshold(count)<frame_w)?new_base:old_base;
  if(addr!==expect_base+count)$fatal(1,"wrong pixel/source at %d addr=%d expected=%d w=%d",count,addr,expect_base+count,frame_w);
  if(last_en && addr!==last_addr+1)$fatal(1,"non-contiguous SDRAM requests inside burst");
  current[count]=(expect_base==new_base);count=count+1;
  if(expect_base==new_base)new_count=new_count+1;else old_count=old_count+1;
 end
 last_addr=addr;last_en=en;
end
 task render;input integer weight;input reverse;begin
 @(negedge clk);idx=reverse?1:0;target=reverse?0:1;progress=weight;
 old_base=reverse?B:A;new_base=reverse?A:B;frame_w=weight;
 repeat(8)@(negedge clk);count=0;old_count=0;new_count=0;current=0;
 req=1;wait(ack);@(negedge clk);req=0;wait(!ack);
 wait(count>32);@(negedge clk);progress=256-weight;target=idx;
 wait(done);@(negedge clk);
 if(count!=N)$fatal(1,"frame length %d",count);
 if(weight==0 && new_count!=0)$fatal(1,"zero endpoint");
 if(weight==256 && old_count!=0)$fatal(1,"full endpoint");
 if(weight>0 && weight<256 && (old_count==0 || new_count==0))$fatal(1,"intermediate frame was all one source");
 if(!reverse && ((prior & ~current)!=0))$fatal(1,"particle reappeared");
 if(!reverse)prior=current;
 $display("PASS particle frame w=%d reverse=%d A=%d B=%d",weight,reverse,old_count,new_count);
 repeat(5)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 render(0,0);render(64,0);render(128,0);render(192,0);render(256,0);render(128,1);
 $display("PASS particle addresses, monotonic reveal, endpoints, frame snapshot, sequential bursts");$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
