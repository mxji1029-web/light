`timescale 1ns/1ps
// Same metadata/SD boundary isolation as tb_album_navigation. Exercises the
// actual navigation state machine, without inventing a second implementation.
module tb_album_pause;
reg clk=0;always #5 clk=~clk;
reg rst=1,paused=1,hold=0,init=0,scanvalid=0,scandone=0,key=0,autokey=0,wrfinish=0;
reg[31:0] sector=0;
wire commit;wire[5:0] photo;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.AUTO_PLAY_MS(100)) dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_finish_toggle(wrfinish),.write_req_ack(1'b0),.SD_MISO(1'b1),.pcm_room_ok(1'b0),
 .hold(hold),.paused(paused),.disp_commit_toggle(commit),.photo_index(photo));
task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
task finish_load;input integer expected;reg oldcommit;begin
 wait(dut.load_start_pulse);#1;
 if(dut.load_sector!==32'd1000+expected*32'd2000)$fatal(1,"paused load wrong LBA");
 oldcommit=commit;tick(6);wrfinish=~wrfinish;wait(commit!=oldcommit);#1;
 if(photo!=expected)$fatal(1,"paused load failed safe completion");
 hold=1;tick(6);hold=0;tick(6);
end endtask
integer i,saved_count,saved_watchdog;
initial begin
 force dut.sd_init_done=init;force dut.bmp_ready=1'b1;
 force dut.scan_found_valid=scanvalid;force dut.scan_done=scandone;
 force dut.scan_found_sector=sector;force dut.catalog_reset=1'b0;
 force dut.catalog_valid=1'b1;force dut.catalog_audio_sector=32'd7;
 force dut.key_next_press=key;force dut.key_auto_press=autokey;
 tick(4);rst=0;init=1;tick(6);
 for(i=0;i<3;i=i+1)begin scanvalid=1;sector=1000+i*2000;tick(1);end
 scanvalid=0;scandone=1;finish_load(0);
 // Switching auto mode during pause may update the mode, never a photo.
 autokey=1;tick(1);autokey=0;tick(120);
 if(!dut.auto_play_en || dut.load_busy || photo!=0 || dut.auto_cnt!=0)
  $fatal(1,"auto-mode toggle advanced photos while paused");
 // Manual navigation retains its old behavior, and in-flight work finishes.
 key=1;tick(1);key=0;finish_load(1);
 paused=0;tick(34);paused=1;tick(5);saved_count=dut.auto_cnt;
 if(saved_count<20 || saved_count>40)$fatal(1,"autoplay did not count active time");
 tick(180);
 if(dut.auto_cnt!=saved_count || dut.load_busy)$fatal(1,"paused autoplay timer advanced or reset");
 hold=1;tick(6);saved_watchdog=dut.hold_cnt;tick(140);
 if(dut.hold_cnt!=saved_watchdog)$fatal(1,"pause triggered transition watchdog");
 hold=0;tick(6);paused=0;
 finish_load(2);
 $display("PASS album pause: boot first photo, paused auto-mode toggle, manual safe completion, autoplay timer freeze/resume, transition watchdog freeze");$finish;
end
initial begin #200000;$fatal(1,"album pause timeout");end
endmodule
