`timescale 1ns/1ps
module tb_commit_guard;
reg clk=0,rst=1,wrfin=0,hold=0,key=0,scanvalid=0,scandone=0,catreset=0;
always #5 clk=~clk;
reg[31:0] sector=0;wire commit;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.write_finish_toggle(wrfin),.write_req_ack(1'b0),
 .SD_MISO(1'b1),.pcm_room_ok(1'b0),.hold(hold),.disp_commit_toggle(commit));
integer i;reg oldcommit;
 task keypress;begin @(negedge clk);key=1;@(negedge clk);key=0;end endtask
 task finish_write;begin oldcommit=commit;repeat(6)@(negedge clk);wrfin=~wrfin;wait(commit!=oldcommit);@(negedge clk);end endtask
initial begin
 force dut.sd_init_done=1'b1;force dut.bmp_ready=1'b1;
 force dut.scan_found_valid=scanvalid;force dut.scan_done=scandone;
 force dut.scan_found_sector=sector;force dut.catalog_reset=catreset;
 force dut.catalog_valid=1'b1;force dut.catalog_audio_sector=32'd7;
 force dut.key_next_press=key;force dut.key_auto_press=1'b0;
 repeat(5)@(negedge clk);rst=0;
 repeat(5)@(negedge clk);catreset=1;@(negedge clk);catreset=0;
 for(i=0;i<3;i=i+1)begin scanvalid=1;sector=100+i*100;@(negedge clk);end
 scanvalid=0;scandone=1;
 wait(dut.load_start_pulse);finish_write;
 hold=1;repeat(8)@(negedge clk);hold=0;repeat(8)@(negedge clk);
 keypress;wait(dut.load_start_pulse);keypress; // queue another next during image2 load
 finish_write;
 repeat(16)begin
  @(negedge clk);if(dut.load_start_pulse || dut.load_sector!=200)$fatal(1,"image3 write raced ahead of video busy acknowledgement");
 end
 hold=1;
 repeat(20)begin @(negedge clk);if(dut.load_start_pulse)$fatal(1,"old frame overwritten during transition");end
 hold=0;wait(dut.load_start_pulse);#1;
 if(dut.load_sector!=300)$fatal(1,"queued next was lost");
 $display("PASS commit guard: queued next waits across delayed busy rise and full transition");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
