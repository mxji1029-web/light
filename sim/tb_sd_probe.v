`timescale 1ns/1ps
module tb_sd_probe;
reg clk=0; always #5 clk=~clk;
reg rst=1;
reg key_next=1, key_auto=1;
wire [3:0] state_code; wire [5:0] photo;
wire [1:0] wbuf,dbuf; wire disp_valid,commit,hold_busy,wr_req,wr_en;
wire [31:0] wr_data; wire sd_ncs,sd_dclk,sd_mosi; wire pcm_we; wire [31:0] pcm_data; wire pcm_found;
reg wr_ack=0; reg wrfin=0;
sd_card_bmp #(.CATALOG_MAGIC(32'h31594c41),.CLK_FREQ_HZ(100_000_000),.AUTO_PLAY_MS(2),
              .SCAN_TARGET_COUNT(7'd64),.DEBOUNCE_MS(1))
 dut(.clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.state_code(state_code),
  .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(disp_valid),
  .write_finish_toggle(wrfin),.write_buf_idx(wbuf),.disp_buf_idx(dbuf),
  .write_req(wr_req),.write_req_ack(wr_ack),.write_en(wr_en),.write_data(wr_data),
  .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(1'b1),
  .pcm_fifo_we(pcm_we),.pcm_fifo_data(pcm_data),.pcm_room_ok(1'b1),.pcm_found(pcm_found),
  .hold(1'b0),.disp_commit_toggle(commit),.photo_index(photo));
always @(posedge clk) wr_ack <= wr_req;
always @(posedge clk) begin
 if (rst) ;
 else if (dut.sd_sec_read_data_valid && dut.bmp_read_m0.rd_cnt<8)
  $display("  sec=%0d rd=%0d byte=%02x", dut.sd_addr_mux, dut.bmp_read_m0.rd_cnt, dut.sd_sec_read_data);
 if (dut.bmp_read_m0.state==3'd5 && dut.bmp_read_m0.cat_cursor==dut.bmp_read_m0.cat_count)
  $display("CHECK cursor=%0d sum=%08x chk=%08x bad=%b a0=%0d a1=%0d a2=%0d last=%0d",
   dut.bmp_read_m0.cat_cursor, dut.bmp_read_m0.cat_sum, dut.bmp_read_m0.cat_checksum,
   dut.bmp_read_m0.cat_bad, dut.bmp_read_m0.cat_addresses[0], dut.bmp_read_m0.cat_addresses[1],
   dut.bmp_read_m0.cat_addresses[2], dut.bmp_read_m0.cat_addresses[11]);
 if (dut.bmp_read_m0.state==3'd1 && dut.sd_sec_read_end)
  $display("SCAN end addr=%0d magic=%08x cnt=%0d aud=%0d chk=%08x sum=%08x", dut.sd_addr_mux,
   dut.bmp_read_m0.cat_magic, dut.bmp_read_m0.cat_count, dut.bmp_read_m0.cat_audio,
   dut.bmp_read_m0.cat_checksum, dut.bmp_read_m0.cat_sum);
end
integer i;
always @(posedge clk) if (dut.scan_found_valid) $display("  emit: sector=%0d count=%0d cursor=%0d bmp_total=%0d", dut.scan_found_sector, dut.img_found_count, dut.bmp_read_m0.cat_cursor, dut.bmp_read_m0.scan_found_total);
initial begin
 repeat(20) @(posedge clk); rst=0;
 for (i=0;i<12;i=i+1) begin
  #200_000;
  $display("t=%0t st=%0d rd=%0d magic=%08x cnt=%0d aud=%0d sum=%08x chk=%08x req=%b addr=%0d end=%b valid=%b catv=%b scandone=%b",
   $time, dut.bmp_read_m0.state, dut.bmp_read_m0.rd_cnt, dut.bmp_read_m0.cat_magic,
   dut.bmp_read_m0.cat_count, dut.bmp_read_m0.cat_audio, dut.bmp_read_m0.cat_sum,
   dut.bmp_read_m0.cat_checksum, dut.sd_req_mux, dut.sd_addr_mux,
   dut.sd_sec_read_end, dut.sd_sec_read_data_valid, dut.catalog_valid, dut.scan_done);
  $fflush;
 end
 $finish;
end
endmodule
