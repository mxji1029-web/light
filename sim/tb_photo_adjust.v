`timescale 1ns/1ps
module tb_photo_adjust;
reg clk=0,rst=1,vs=1,hs=1,de=0,active=0,selected=0;
reg[23:0] rgb=0;reg signed[7:0] brightness=0;reg[2:0] contrast=2;
wire ho,vo,dout,frame_active,frame_selected;wire[23:0] out;
wire signed[7:0] frame_brightness;wire[2:0] frame_contrast;
always #5 clk=~clk;
photo_adjust dut(clk,rst,hs,vs,de,rgb,brightness,contrast,active,selected,
 ho,vo,dout,out,frame_brightness,frame_contrast,frame_active,frame_selected);
integer ref_b=0,ref_c=2,l,b,v,checked=0;
reg[23:0] expected0=0,expected1=0;reg[2:0] sync0=0,sync1=0;
function[7:0] channel;input integer c;integer product,result,magnitude,whole,remainder;begin
 product=(c-128)*(32+16*ref_c);
 magnitude=product<0?-product:product;whole=magnitude/64;remainder=magnitude%64;
 if(remainder>32 || (remainder==32 && whole%2))whole=whole+1;
 result=(product<0?-whole:whole)+128+ref_b;
 channel=result<0?0:result>255?255:result;
end endfunction
always @(posedge clk)begin
 if(rst)begin expected0=0;expected1=0;sync0=0;sync1=0;end
 else begin
  expected1=expected0;expected0={channel(rgb[23:16]),channel(rgb[15:8]),channel(rgb[7:0])};
  sync1=sync0;sync0={hs,vs,de};
 end
 #1;
 if(!rst && {ho,vo,dout}!==sync1)$fatal(1,"adjust sync not two cycles");
 if(!rst && dout)begin
  if(out!==expected1)$fatal(1,"brightness %0d contrast %0d output %h expected %h",ref_b,ref_c,out,expected1);
  checked=checked+1;
 end
end
task frame;begin
 @(negedge clk);vs=0;de=0;ref_b=brightness;ref_c=contrast;
 repeat(4)@(negedge clk);vs=1;repeat(4)@(negedge clk);
 if(frame_brightness!==brightness || frame_contrast!==contrast || frame_active!==active || frame_selected!==selected)
  $fatal(1,"frame snapshot does not match applied settings");
end endtask
initial begin
 #12;rst=0;frame;
 for(l=0;l<5;l=l+1)for(b=-64;b<=64;b=b+8)begin
  contrast=l;brightness=b;frame;
  for(v=0;v<256;v=v+1)begin
   @(negedge clk);de=1;rgb={v[7:0],8'd255-v[7:0],(v[7:0]*8'd37)};
  end
  @(negedge clk);de=0;repeat(4)@(negedge clk);
 end
 brightness=0;contrast=2;active=1;selected=1;frame;
 // Live changes during an active frame must not alter picture or OSD values.
 brightness=64;contrast=4;active=0;selected=0;
 repeat(12)begin @(negedge clk);de=1;rgb=24'h00a5ff;end
 if(frame_brightness!=0 || frame_contrast!=2 || !frame_active || !frame_selected)
  $fatal(1,"live settings tore the active frame");
 @(negedge clk);de=0;frame;
 repeat(12)begin @(negedge clk);de=1;rgb=24'h00a5ff;end
 @(negedge clk);de=0;repeat(4)@(negedge clk);
 $display("PASS photo adjustment: %0d RGB vectors, 5x17 settings, saturation, default identity, frame lock and two-cycle sync",checked);$finish;
end
endmodule
