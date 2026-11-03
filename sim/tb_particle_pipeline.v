`timescale 1ns/1ps
// Production request/ACK, 21-clock video delay and transition controller in one
// test. SDRAM responses have six clocks of latency; write bursts occupy 256
// memory clocks. No controller-internal signals are forced.
module tb_particle_pipeline #(parameter STYLE_TO_TEST=0, MULTI_TEST=0);
reg mc=0,vc=0,rst=1;always #4 mc=~mc;always #20 vc=~vc;
wire hs0,vs0,de0,req,ack,read_en,hs,vs,de;
reg swap=0;reg[1:0] idx=0;reg[5:0] id=0;
wire[3:0] style;wire[1:0] oldidx,newidx;wire[8:0] progress;wire trbusy;
wire[23:0] raw,rgb;
wire men,clear,rd_busy;wire[20:0] addr;
reg[23:0] fifo_data=0;
video_timing_data timing(.video_clk(vc),.rst(rst),.read_req(req),.read_req_ack(ack),.hs(hs0),.vs(vs0),.de(de0));
defparam timing.color_bar_m0.H_ACTIVE=64,timing.color_bar_m0.H_FP=4,timing.color_bar_m0.H_SYNC=8,timing.color_bar_m0.H_BP=8;
defparam timing.color_bar_m0.V_ACTIVE=48,timing.color_bar_m0.V_FP=2,timing.color_bar_m0.V_SYNC=2,timing.color_bar_m0.V_BP=3;
video_delay delay_video(.video_clk(vc),.rst(rst),.read_en(read_en),.read_data(fifo_data),
 .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(raw));
photo_transition #(.FADE_FRAMES(8),.MULTI_TRANSITIONS(MULTI_TEST)) transition(.clk(vc),.rst(rst),.hs_in(hs),.vs_in(vs),.de_in(de),.rgb_in(raw),
 .swap_toggle(swap),.new_idx(idx),.new_photo_id(id),.shown_photo_id(),.shown_toggle(),
 .read_idx(oldidx),.busy(trbusy),.hs_out(),.vs_out(),.de_out(),.rgb_out(rgb),
 .reveal_idx(newidx),.reveal_progress(progress),.reveal_style(style));
integer write_ptr=0,read_ptr=0,cycles=0,occupancy=0;
reg[20:0] fifo[0:1023];reg[5:0] valid_pipe=0;reg[20:0] addr_pipe[0:5];
wire write_busy=(cycles%1200)<256;
wire[9:0] used=write_ptr-read_ptr;
frame_fifo_read #(.PARTICLE_TRANSITION(1),.MULTI_TRANSITIONS(MULTI_TEST),.FRAME_WIDTH(64),.BURST_SIZE(16)) reader(
 .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(valid_pipe[5]),.App_wr_busy(write_busy),.O_rd_busy(rd_busy),.App_rd_en(men),.App_rd_addr(addr),
 .read_req(req),.read_req_ack(ack),.read_finish(),.read_addr_0(21'd0),.read_addr_1(21'd307200),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(oldidx),.read_len(21'd3072),
 .fifo_aclr(clear),.wrusedw(used),.reveal_style(style),.reveal_idx(newidx),.reveal_progress(progress));
integer j;reg started=0;reg[8:0] frame_progress=0;reg[1:0] frame_old=0,frame_new=0;reg ack_d=0;
always @(posedge mc)begin
 cycles<=cycles+1;
 if(rst || clear)begin write_ptr=0;valid_pipe<=0;end
 else begin
  valid_pipe<={valid_pipe[4:0],men};addr_pipe[0]<=addr;
  for(j=1;j<6;j=j+1)addr_pipe[j]<=addr_pipe[j-1];
  if(valid_pipe[5])begin
   if(write_ptr-read_ptr>=512)$fatal(1,"read FIFO overflow");
   fifo[write_ptr%1024]=addr_pipe[5];write_ptr=write_ptr+1;
  end
 end
 if(!rst && ack_d && !ack)begin
  if(reader.progress_latch!==progress || reader.style_latch!==style || reader.read_addr_index_d1!==oldidx)
   $fatal(1,"frame descriptor did not latch source controls");
  frame_progress=progress;frame_old=oldidx;frame_new=newidx;frame_style=style;started=1;
 end
 ack_d=ack;
end
reg[20:0] item;integer expected_offset=0;integer frame_style=0,oracle_index;
reg oracle[0:74015];
initial $readmemh("D:/FPGA/competition/03_dev/oral_album_lyrics28/sim/multi_transition_oracle.hex",oracle);
function integer threshold;input integer offset;reg[15:0] a,b,t;reg[7:0] h;
begin a=((offset%64)>>4)*40503;b=((offset/64)>>3)*34283;t=a^b;h=t[7:0]^t[15:8];threshold=h^(h>>3);end
endfunction
integer expected_base;
always @(posedge vc or posedge clear)begin
 if(clear || rst)begin read_ptr=0;fifo_data<=0;expected_offset=0;end
 else if(read_en && started)begin
  if(write_ptr<=read_ptr)$fatal(1,"read FIFO underflow with 16-pixel bursts and write competition");
  item=fifo[read_ptr%1024];read_ptr=read_ptr+1;
  expected_base=(frame_progress==256 || threshold(expected_offset)<frame_progress)?(frame_new?307200:0):(frame_old?307200:0);
  if(MULTI_TEST)begin
   oracle_index=(frame_style*257+frame_progress)*24+(expected_offset/64/8)*4+((expected_offset%64)/16);
   expected_base=oracle[oracle_index]?(frame_new?307200:0):(frame_old?307200:0);
  end
  if(item!==expected_base+expected_offset)$fatal(1,"frame snapshot/pixel alignment mismatch offset=%d item=%d expected=%d",expected_offset,item,expected_base+expected_offset);
  expected_offset=expected_offset+1;
  fifo_data<=item>=307200?24'h3070b0:24'hd08040;
 end
end
integer intermediate_frames=0,seen_a=0,seen_b=0;reg de_prev=0,vs_prev=1;
always @(negedge vc)begin
 if(!rst && started)begin
  if(de)begin
   if(rgb==24'hd08040)seen_a=seen_a+1;
   else if(rgb==24'h3070b0)seen_b=seen_b+1;
   else $fatal(1,"solid backdrop or missing photo pixel %h",rgb);
  end
  if(vs_prev && !vs)begin
   if(seen_a && seen_b)intermediate_frames=intermediate_frames+1;
   seen_a=0;seen_b=0;
  end
 end
 vs_prev=vs;
end
initial begin
 repeat(8)@(negedge vc);id=(STYLE_TO_TEST==11)?11:0;rst=0;swap=1;
 wait(trbusy);wait(!trbusy);repeat(6000)@(negedge vc);
 idx=1;id=(STYLE_TO_TEST==11)?0:STYLE_TO_TEST+1;swap=0;wait(trbusy);wait(!trbusy);
 repeat(5000)@(negedge vc);
 if(intermediate_frames<(MULTI_TEST?1:5))$fatal(1,"no real mixed-source frames: %d",intermediate_frames);
 $display("PASS actual VS->request->ACK->FIFO->21-clock delay->particles: %d mixed frames, no starvation under write competition",intermediate_frames);$finish;
end
initial begin #6000000;$fatal(1,"timeout");end
endmodule
