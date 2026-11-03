`timescale 1ns/1ps
// Board-level picture switching test.
//
// Instantiates the real sd_card_bmp (catalog scan, bmp_read, SD arbiter, PCM
// reader) and the real photo_transition, and replaces only the SPI layer with
// sim/sd_card_stub.v (compile with -DTB_FAKE_SD). Verifies that KEY2 (next) and
// KEY4 (auto play) really load the next picture while music is streaming.
module tb_board_switch;
reg clk=0;
always #5 clk=~clk;
reg rst=1;
reg key_next=1, key_auto=1;
wire [3:0] state_code;
wire [5:0] photo, shown_photo;
wire [1:0] wbuf, dbuf;
wire disp_valid, commit, hold_busy;
wire wr_req;
reg  wr_ack=0;
wire wr_en;
wire [31:0] wr_data;
wire sd_ncs, sd_dclk, sd_mosi;
wire pcm_we;
wire [31:0] pcm_data;
wire pcm_found;
reg  wrfin=0;
integer written=0;
reg hs=1, vs=1, de=0;
integer vcnt=0;

sd_card_bmp #(.CATALOG_MAGIC(32'h31594c41),.CLK_FREQ_HZ(100_000_000),.AUTO_PLAY_MS(2),
              .SCAN_TARGET_COUNT(7'd64),.DEBOUNCE_MS(1))
 dut(.clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.state_code(state_code),
  .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(disp_valid),
  .write_finish_toggle(wrfin),.write_buf_idx(wbuf),.disp_buf_idx(dbuf),
  .write_req(wr_req),.write_req_ack(wr_ack),.write_en(wr_en),.write_data(wr_data),
  .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(1'b1),
  .pcm_fifo_we(pcm_we),.pcm_fifo_data(pcm_data),.pcm_room_ok(1'b1),.pcm_found(pcm_found),
  .hold(hold_busy),.disp_commit_toggle(commit),.photo_index(photo));

photo_transition u_tr(.clk(clk),.rst(rst),.hs_in(hs),.vs_in(vs),.de_in(de),
 .rgb_in(24'h404040),.swap_toggle(commit),.new_idx(dbuf),.new_photo_id(photo),
 .shown_photo_id(shown_photo),.shown_toggle(),.read_idx(),.busy(hold_busy),
 .hs_out(),.vs_out(),.de_out(),.rgb_out());

// synthetic video timing: one "frame" every 200 clocks, de high for 100
always @(posedge clk) begin
 if (rst) begin vcnt<=0; vs<=1; de<=0; end
 else begin
  vcnt<=vcnt+1;
  if (vcnt>=200) vcnt<=0;
  if (vcnt==0) vs<=0; else if (vcnt==4) vs<=1;
  de <= (vcnt>10)&&(vcnt<110);
 end
end

// frame writer stub: ack the request, report a finished frame after 307200 pixels
always @(posedge clk) begin
 if (rst) begin wr_ack<=0; written<=0; end
 else begin
  wr_ack <= wr_req;
  if (wr_en) begin
   written <= written+1;
   if (written+1 >= 307200) begin wrfin<=~wrfin; written<=0; end
  end
 end
end

integer errors=0;
reg [31:0] first_sec, second_sec;
task press_next; begin
 key_next=0; repeat(150_000) @(posedge clk); key_next=1; repeat(20_000) @(posedge clk);
end endtask
task press_auto; begin
 key_auto=0; repeat(150_000) @(posedge clk); key_auto=1; repeat(20_000) @(posedge clk);
end endtask
task wait_idle;   // loader finished and the reader is back in its idle state
 integer guard;
 begin
  guard=0;
  // Quality-mode identity includes two row-cache fills/interpolation per line;
  // allow 200ms virtual time while retaining a finite liveness bound.
  while (!(dut.load_busy==1'b0 && dut.bmp_ready==1'b1) && guard<20_000_000) begin @(posedge clk); guard=guard+1; end
  if (guard>=20_000_000) begin $display("FAIL: loader never went idle"); errors=errors+1; end
 end
endtask
task wait_sector;
 input [31:0] previous;
 integer guard;
 begin
  guard=0;
  while (dut.load_sector === previous && guard<8_000_000) begin @(posedge clk); guard=guard+1; end
  if (guard>=8_000_000) begin
   $display("FAIL: no new load: state=%0d found=%0d load_busy=%0d hold=%0d ready=%0d valid=%0d",
            dut.state_code,dut.img_found_count,dut.load_busy,dut.hold_sync,dut.bmp_ready,dut.display_valid);
   errors=errors+1;
  end
 end
endtask
initial begin
 repeat(20) @(posedge clk); rst=0;
 wait (dut.scan_done);
 $display("scan done: img_found_count=%0d catalog_valid=%0d", dut.img_found_count, dut.catalog_valid); $fflush;
 wait (dut.first_image_committed);
 first_sec = dut.load_sector;
 $display("first image: sector=%0d photo=%0d display_valid=%0d", first_sec, photo, disp_valid); $fflush;
 wait_idle();
 repeat(3000) @(posedge clk);

 press_next();
 $display("after KEY2 press: pending=%b found=%0d hold=%b load_busy=%b ready=%b valid=%b",
          dut.next_req_pending, dut.img_found_count, dut.hold_sync, dut.load_busy, dut.bmp_ready, dut.display_valid); $fflush;
 wait_sector(first_sec);
 second_sec = dut.load_sector;
 if (second_sec !== (first_sec+100)) begin
  $display("FAIL: KEY2 loaded sector %0d, expected %0d", second_sec, first_sec+100);
  errors=errors+1;
 end else $display("KEY2 loaded sector %0d", second_sec);
 $fflush;
 wait_idle();

 press_auto();
 $display("after KEY4 press: auto_en=%b found=%0d", dut.auto_play_en, dut.img_found_count); $fflush;
 wait_sector(second_sec);
 if (dut.load_sector === second_sec) begin
  $display("FAIL: auto play did not advance (still %0d)", dut.load_sector);
  errors=errors+1;
 end else $display("KEY4 auto play loaded sector %0d", dut.load_sector);
 $fflush;

 if (errors==0) $display("PASS board switch: KEY2 and KEY4 both advance the picture");
 else $fatal(1,"board switch: %0d error(s)", errors);
 $finish;
end
initial begin #500_000_000; $fatal(1,"board switching timeout at %0t", $time); end
endmodule
