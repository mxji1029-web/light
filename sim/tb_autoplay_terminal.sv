`timescale 1ns/1ps
// Counter/control-plane equivalence using both actual module versions. Card
// and pixel IP are omitted; their held status and handshake inputs are driven.
module tb_autoplay_terminal;
parameter integer COUNT=100;
reg clk=0,rst=1,paused=0,hold=0,wrfin=0,initialized=0,next_press=0,auto_press=0;
always #5 clk=~clk;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.AUTO_PLAY_MS(COUNT)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.write_finish_toggle(wrfin),
 .hold(hold),.paused(paused),.write_req_ack(1'b0),.SD_MISO(1'b1),.pcm_room_ok(1'b1));
sd_card_bmp_reference #(.CLK_FREQ_HZ(1000),.AUTO_PLAY_MS(COUNT)) reference(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.write_finish_toggle(wrfin),
 .hold(hold),.paused(paused),.write_req_ack(1'b0),.SD_MISO(1'b1),.pcm_room_ok(1'b1));
integer cycle,compared=0,ticks=0;
initial begin
 force dut.sd_init_done=initialized;force reference.sd_init_done=initialized;
 force dut.bmp_ready=1;force reference.bmp_ready=1;
 force dut.scan_done=1;force reference.scan_done=1;
 force dut.scan_found_valid=0;force reference.scan_found_valid=0;
 force dut.catalog_reset=0;force reference.catalog_reset=0;
 force dut.img_found_count=3;force reference.img_found_count=3;
 force dut.key_next_press=next_press;force reference.key_next_press=next_press;
 force dut.key_auto_press=auto_press;force reference.key_auto_press=auto_press;
 dut.img_sectors[0]=100;reference.img_sectors[0]=100;
 dut.img_sectors[1]=200;reference.img_sectors[1]=200;
 dut.img_sectors[2]=300;reference.img_sectors[2]=300;
 repeat(4)@(negedge clk);rst=0;initialized=1;
 for(cycle=0;cycle<30000;cycle=cycle+1)begin
  @(negedge clk);
  paused=(cycle>11000 && cycle%251<47);
  hold=(dut.commit_wait && !dut.commit_hold_seen) || (cycle>11000 && cycle%61<4);
  next_press=cycle>10000 && cycle%113==0;
  auto_press=cycle==80 || (cycle>12000 && cycle%2000==0);
  initialized=!(cycle>15000 && cycle%6000<3);
  if(cycle%19==0)wrfin=~wrfin;
  @(posedge clk);#1;
  if(dut.auto_tick!==(dut.auto_cnt==COUNT-1))$fatal(1,"terminal/count invariant COUNT%0d cycle%0d got%0d count%0d",COUNT,cycle,dut.auto_tick,dut.auto_cnt);
  if({dut.auto_tick,dut.auto_cnt,dut.load_start_pulse,dut.load_sector,dut.img_idx,dut.disp_commit_toggle,dut.auto_play_en,dut.next_req_pending} !==
     {reference.auto_tick,reference.auto_cnt,reference.load_start_pulse,reference.load_sector,reference.img_idx,reference.disp_commit_toggle,reference.auto_play_en,reference.next_req_pending})$fatal(1,"cycle mismatch COUNT%0d cycle%0d",COUNT,cycle);
  compared=compared+1;if(dut.auto_tick)ticks=ticks+1;
 end
 if(ticks==0)$fatal(1,"never exercised terminal");
 $display("PASS exact autoplay lookahead COUNT=%0d cycles=%0d terminal=%0d; init/pause/hold/manual/autoplay/commit unchanged",COUNT,compared,ticks);$finish;
end
endmodule
