`timescale 1ns/1ps
// Renders photo_transition frames to PPM so the dissolve/drift/hot-edge look can
// be inspected. Video timing is shortened (active 640x480, tiny blanking) and
// the fade is compressed to 8 frames per phase: the pixel math is identical.
module tb_transition;
localparam W = 640, H = 480;
localparam HTOTAL = 656, VTOTAL = 490;
reg clk=0; always #20 clk=~clk;      // 25 MHz pixel clock
reg rst=1;
reg [10:0] hx=0, vy=0;
reg hs=0, vs=0, de=0;
reg swap=0;
wire [1:0] rd_idx;
wire busy, shown_tog;
wire [5:0] shown_id;
wire hs_o, vs_o, de_o;
wire [23:0] rgb_o;

// synthetic "photo": sky gradient + sun + ground + a few blobs
function [23:0] photo;
 input integer x, y;
 reg [7:0] r,g,b;
 begin
  r = 40 + (y*160)/H; b = 120 + (y*90)/H; g = 90 + (y*70)/H;
  if ((x-470)*(x-470) + (y-120)*(y-120) < 3600) begin r=255; g=232; b=150; end
  if (y > 330) begin r = 70+(x*60)/W; g = 110+(x*40)/W; b = 60+(x*30)/W; end
  if ((x-160)*(x-160) + (y-380)*(y-380) < 2500) begin r=200; g=60; b=70; end
  if (x>260 && x<380 && y>250 && y<320) begin r=240; g=240; b=235; end
  photo = {r,g,b};
 end
endfunction

wire [23:0] rgb_in = photo(hx[9:0], vy[9:0]);

photo_transition #(.FADE_FRAMES(16'd8)) dut(
 .clk(clk),.rst(rst),.hs_in(hs),.vs_in(vs),.de_in(de),.rgb_in(rgb_in),
 .swap_toggle(swap),.new_idx(2'd1),.new_photo_id(6'd1),
 .shown_photo_id(shown_id),.shown_toggle(shown_tog),.read_idx(rd_idx),.busy(busy),
 .hs_out(hs_o),.vs_out(vs_o),.de_out(de_o),.rgb_out(rgb_o));

// video timing
always @(posedge clk) begin
 if (rst) begin hx<=0; vy<=0; hs<=1; vs<=1; de<=0; end
 else begin
  if (hx == HTOTAL-1) begin
   hx <= 0;
   if (vy == VTOTAL-1) vy <= 0; else vy <= vy + 1;
   vs <= (vy >= H+2) && (vy < H+4);
   hs <= 1;
  end else begin
   hx <= hx + 1;
   if (hx == W) hs <= 0;
   else if (hx == W+4) hs <= 1;
  end
  de <= (hx < W) && (vy < H);
 end
end

// frame capture
reg [7:0] fbuf [0:W*H*3-1];
integer idx=0, frame=0;
reg dumping=0;
always @(posedge clk) begin
 if (!rst && de && de_o && hx < W && vy < H) begin
  fbuf[idx*3+0] <= rgb_o[23:16];
  fbuf[idx*3+1] <= rgb_o[15:8];
  fbuf[idx*3+2] <= rgb_o[7:0];
  idx <= idx + 1;
 end
 if (!rst && hx == HTOTAL-1 && vy == H-1) begin
  idx <= 0;
  frame <= frame + 1;
 end
end

integer fd, k;
task dump_frame;
 input [255:0] name;
 begin
  fd = $fopen(name, "wb");
  $fwrite(fd, "P6\n640 480\n255\n");
  for (k=0; k<W*H*3; k=k+1) $fwrite(fd, "%c", fbuf[k]);
  $fclose(fd);
  $display("wrote %0s", name);
  $fflush;
 end
endtask

always @(posedge clk) if (rst===1'b0 && hx==0 && vy==H)
 $display("f=%0d state=%0d w=%0d busy=%b sw=%b last=%b black=%b", frame, dut.state, dut.w, dut.busy, dut.swap_sync[1], dut.swap_last, dut.use_black);

// sequence: boot commit at frame 1, a real picture switch at frame 12
integer f;
integer dump_at [0:22];
reg [255:0] fname;
initial begin
 dump_at[0]=12; dump_at[1]=13; dump_at[2]=14; dump_at[3]=15; dump_at[4]=16;
 dump_at[5]=17; dump_at[6]=18; dump_at[7]=19; dump_at[8]=20; dump_at[9]=21;
 dump_at[10]=22; dump_at[11]=23; dump_at[12]=24; dump_at[13]=25; dump_at[14]=26;
 dump_at[15]=27; dump_at[16]=28; dump_at[17]=29; dump_at[18]=30; dump_at[19]=31;
 dump_at[20]=32; dump_at[21]=33; dump_at[22]=34;
 repeat(4) @(posedge clk); rst=0;
 while (frame < 1) @(posedge clk);
 swap <= 1;                       // 第一次提交：开机从黑场聚出首图
 while (frame < 12) @(posedge clk);
 swap <= 0;                       // 第二次提交：真正的一次图片切换
 for (f=0; f<23; f=f+1) begin
  while (frame < dump_at[f]) @(posedge clk);
  while (!(vy == H && hx == 0)) @(posedge clk);
  repeat(2) @(posedge clk);
  $sformat(fname, "sim/out/frame_%02d.ppm", frame);
  fd = $fopen(fname, "wb");
  $fwrite(fd, "P6\n640 480\n255\n");
  for (k=0; k<W*H*3; k=k+1) $fwrite(fd, "%c", fbuf[k]);
  $fclose(fd);
  $display("wrote %0s (frame %0d)", fname, frame);
  $fflush;
 end
 $display("done");
 $finish;
end
initial begin #600_000_000; $display("timeout"); $finish; end
endmodule