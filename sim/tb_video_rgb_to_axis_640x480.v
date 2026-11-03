`timescale 1ns/1ps
module tb_video_rgb_to_axis_640x480;
reg clk=0,rst=0,vs=1,de=0;reg[23:0] rgb=0;
wire user,valid,last;wire[23:0] data;
always #5 clk=~clk;
video_rgb_to_axis_640x480 dut(clk,rst,vs,de,rgb,user,valid,last,data);

integer checked_cycles=0,checked_pixels=0,checked_blank=0;
integer checked_lines=0,checked_frames=0,reset_checks=0;
task cycle;
 input next_de,next_vs;input[23:0] next_rgb;input expected_user,expected_last;
 begin
  @(negedge clk);de=next_de;vs=next_vs;rgb=next_rgb;
  @(posedge clk);#1;
  if(valid!==next_de || data!==next_rgb)
   $fatal(1,"registered RGB/valid mismatch cycle%0d: %b/%h expected%b/%h",checked_cycles,valid,data,next_de,next_rgb);
  if(user!==expected_user || last!==expected_last)
   $fatal(1,"SOF/TLAST mismatch cycle%0d: user%0b last%0b expected%0b/%0b",checked_cycles,user,last,expected_user,expected_last);
  if(!next_de && (user || last))$fatal(1,"control pulse during blanking");
  checked_cycles=checked_cycles+1;
 end
endtask

task reset_outputs;
 begin
  // Assert between clock edges while active data is present.
  #2;rst=1;#1;
  if({user,valid,last,data}!==27'd0)$fatal(1,"asynchronous reset did not clear outputs");
  repeat(3)begin
   @(posedge clk);#1;
   if({user,valid,last,data}!==27'd0)$fatal(1,"outputs changed while reset held");
   reset_checks=reset_checks+1;
  end
  @(negedge clk);de=0;vs=1;rgb=0;rst=0;
 end
endtask

integer frame,y,x,prefix;reg active_pixel;reg[23:0] expected_rgb;
integer frame_pixels,frame_lines,frame_users;
initial begin
 reset_outputs;
 // Interrupt a partially transmitted line, then start with a clean full frame.
 // This catches retained line position and a lost first-pixel frame marker.
 for(prefix=0;prefix<37;prefix=prefix+1)
  cycle(1'b1,1'b1,24'hab0000+prefix,prefix==0,1'b0);
 reset_outputs;
 for(frame=0;frame<2;frame=frame+1)begin
  frame_pixels=0;frame_lines=0;frame_users=0;
  // Complete VGA frame:800 clocks/line,525 lines,640x480 active pixels.
  for(y=0;y<525;y=y+1)begin
   for(x=0;x<800;x=x+1)begin
    active_pixel=(y>=45 && x>=160);
    expected_rgb=active_pixel?(24'h350000^(frame<<20)^((y-45)*640+x-160)):
                              (24'h910000^(y*800+x));
    cycle(active_pixel,y>=2,expected_rgb,active_pixel && y==45 && x==160,
          active_pixel && x==799);
    if(active_pixel)begin
     checked_pixels=checked_pixels+1;frame_pixels=frame_pixels+1;
     if(user)frame_users=frame_users+1;
     if(last)begin checked_lines=checked_lines+1;frame_lines=frame_lines+1;end
    end else checked_blank=checked_blank+1;
   end
  end
  if(frame_pixels!=307200 || frame_lines!=480 || frame_users!=1)
   $fatal(1,"frame%0d counts pixels=%0d last=%0d user=%0d",frame,frame_pixels,frame_lines,frame_users);
  checked_frames=checked_frames+1;
 end
 reset_outputs;
 cycle(1'b0,1'b0,24'h55aa11,1'b0,1'b0);
 $display("PASS video AXIS contract: %0d complete frames, %0d RGB pixels, %0d line-last pulses, 2 SOF, %0d blank cycles; 37-pixel interrupted line and %0d reset checks; one-clock alignment",checked_frames,checked_pixels,checked_lines,checked_blank,reset_checks);
 $finish;
end
endmodule
