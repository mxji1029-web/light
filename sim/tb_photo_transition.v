`timescale 1ns/1ps
module tb_photo_transition;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1, hs=0, vs=1, de=0, swap=0;
  reg [1:0] idx=0;
  reg [5:0] photo_id=0;
  wire [5:0] shown_id;
  wire shown_toggle;
  wire [1:0] read_idx;
  wire busy, ho, vo, deo;
  wire [23:0] rgb;
  photo_transition #(.FADE_FRAMES(4)) dut(
    .clk(clk),.rst(rst),.hs_in(hs),.vs_in(vs),.de_in(de),
    .rgb_in(24'h80a0c0),.swap_toggle(swap),.new_idx(idx),
    .new_photo_id(photo_id),.shown_photo_id(shown_id),.shown_toggle(shown_toggle),
    .read_idx(read_idx),.busy(busy),.hs_out(ho),.vs_out(vo),
    .de_out(deo),.rgb_out(rgb));
  task frame;
    begin
      @(negedge clk); vs=0;
      repeat(3) @(negedge clk);
      vs=1;
      repeat(20) @(negedge clk);
    end
  endtask
  task commit;
    input [1:0] target;
    input integer delay_cycles;
    begin
      @(negedge clk); idx=target; swap=~swap;
      repeat(delay_cycles) @(negedge clk);
    end
  endtask
  integer i;
  reg [1:0] observed_idx=0;
  reg observed_vs=1;
  reg edge_now;
  reg observed_toggle=0;
  integer show_events=0;
  always @(posedge clk) begin
    edge_now=observed_vs && !vs;
    observed_vs=vs;
    #1;
    if(!rst && read_idx!==observed_idx && !edge_now)
      $fatal(1,"display buffer changed outside vertical blanking edge");
    if(!rst && shown_toggle!==observed_toggle)begin
      if(!edge_now || shown_id!==photo_id)$fatal(1,"photo event was not aligned with actual display commit");
      show_events=show_events+1;
    end
    observed_toggle=shown_toggle;
    observed_idx=read_idx;
  end
  initial begin
    repeat(4) @(negedge clk); rst=0;
    // Integration contract: keep the known-good HDMI timing path unchanged.
    // The pixel mixer feeds the existing downstream AXIS output register.
    @(negedge clk); hs=1; de=1; vs=0;
    #1;
    if(ho!==hs || vo!==vs || deo!==de)
      $fatal(1,"transition changed the upstream HDMI timing latency");
    @(negedge clk); hs=0; de=0; vs=1;
    #1;
    if(ho!==hs || vo!==vs || deo!==de || rgb!==0)
      $fatal(1,"transition blanking/timing mismatch");
    // A commit arrives well before the next vertical blanking edge.
    // It must survive until that edge, including a first commit to buffer 0.
    commit(0,12);
    frame;
    if(!busy) $fatal(1,"first commit lost before frame boundary");
    repeat(6) frame;
    if(busy || read_idx!==0) $fatal(1,"first fade did not finish");
    de=1;
    repeat(3) @(negedge clk);
    if(rgb!==24'h80a0c0 || !deo) $fatal(1,"full-opacity pixel mismatch");
    de=0;
    for(i=0;i<64;i=i+1) begin
      photo_id=(i+1)%64; // photo ids 0..3 must not collapse to buffer ids 0..1
      commit((i+1)%2,8+i);
      if(!busy) $fatal(1,"load hold not asserted while commit is pending");
      if(read_idx!==(i%2)) $fatal(1,"buffer changed outside frame boundary");
      repeat(13) frame;
      if(busy || read_idx!==((i+1)%2)) $fatal(1,"subsequent commit lost");
      // No new commit: the same event must not replay.
      repeat(3) frame;
      if(busy) $fatal(1,"commit repeated");
    end
    if(show_events!=65)$fatal(1,"expected exactly 65 display events, got %d",show_events);
    rst=1; repeat(3) @(negedge clk); swap=0; idx=0;photo_id=0;
    rst=0; repeat(3) frame;
    if(busy || read_idx!==0) $fatal(1,"reset did not clear pending commit");
    $display("PASS: pending commits, frame-boundary switching, pixels, reset");
    $finish;
  end
  initial begin #2000000; $fatal(1,"timeout"); end
endmodule
