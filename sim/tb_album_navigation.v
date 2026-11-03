`timescale 1ns/1ps
module tb_album_navigation #(parameter integer IMAGE_COUNT=64);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,wrfinish=0,hold=0;
 wire [5:0] photo;
 wire [1:0] wbuf,dbuf;
 wire commit;
 reg init=0,scanvalid=0,scandone=0,catreset=0,key=0,autokey=0;
 reg [31:0] sector=0;
 integer i,k,load_count=0;
 function[31:0] sector_for;input integer index;begin sector_for=32'hE0000000+index*32'h010101;end endfunction
 sd_card_bmp #(.CLK_FREQ_HZ(1000),.AUTO_PLAY_MS(100)) dut(.clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_finish_toggle(wrfinish),.write_buf_idx(wbuf),
 .disp_buf_idx(dbuf),.write_req_ack(1'b0),.SD_MISO(1'b1),.pcm_room_ok(1'b0),.hold(hold),
 .disp_commit_toggle(commit),.photo_index(photo));
 task finish_load;input integer expected;reg oldcommit;begin
   wait(dut.load_start_pulse);#1;
   if(dut.load_sector!==sector_for(expected))$fatal(1,"wrong load LBA at %0d: %h",expected,dut.load_sector);
   if(wbuf!==(load_count%2))$fatal(1,"frame buffer no longer alternates");
   load_count=load_count+1;
   oldcommit=commit;
   repeat(6)@(negedge clk);wrfinish=~wrfinish;
   wait(commit!=oldcommit);#1;
   if(photo!==expected)$fatal(1,"photo ID truncated: expected %0d got %0d",expected,photo);
   hold=1;repeat(4)@(negedge clk);hold=0;repeat(4)@(negedge clk);
 end endtask
 initial begin
   force dut.sd_init_done=init;force dut.bmp_ready=1'b1;
   force dut.scan_found_valid=scanvalid;force dut.scan_done=scandone;
   force dut.scan_found_sector=sector;force dut.catalog_reset=catreset;
   force dut.catalog_valid=1'b1;force dut.catalog_audio_sector=32'd7;
   force dut.key_next_press=key;force dut.key_auto_press=autokey;
   repeat(4)@(negedge clk);rst=0;init=1;
   repeat(5)@(negedge clk);catreset=1;@(negedge clk);catreset=0;
   for(i=0;i<IMAGE_COUNT;i=i+1)begin scanvalid=1;sector=sector_for(i);@(negedge clk);end
   scanvalid=0;scandone=1;
   finish_load(0);
   if(dut.u_pcm_sd_reader.scan_start!==7)$fatal(1,"explicit BGM LBA lost");
   for(k=1;k<=IMAGE_COUNT;k=k+1)begin key=1;@(negedge clk);key=0;finish_load(k%IMAGE_COUNT);end
   if(dut.img_found_count!==IMAGE_COUNT)$fatal(1,"catalog count overflow");
   autokey=1;@(negedge clk);autokey=0;
   if(IMAGE_COUNT>1)for(k=1;k<=IMAGE_COUNT;k=k+1)finish_load(k%IMAGE_COUNT);
   autokey=1;@(negedge clk);autokey=0;
   repeat(150)@(negedge clk);
   if(dut.load_busy || dut.auto_play_en)$fatal(1,"autoplay did not stop");
   rst=1;repeat(4)@(negedge clk);
   if(dut.img_found_count!==0 || photo!==0)$fatal(1,"reset retained catalog count or ID");
   $display("PASS: %0d distinct full32-bit catalog entries, manual/automatic wrap, frame buffer alternation, BGM locator",IMAGE_COUNT);$finish;
 end
 initial begin #2000000;$fatal(1,"navigation timeout");end
endmodule
