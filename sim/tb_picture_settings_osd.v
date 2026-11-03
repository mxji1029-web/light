`timescale 1ns/1ps
module tb_picture_settings_osd;
reg clk=0,rst=1,vs=1,de=0,active=0;reg[1:0] selected=0;
reg[23:0] rgb=24'hd8a878;reg signed[7:0] brightness=0;reg[2:0] contrast=2;
reg[3:0] volume_level=10;
wire ho,vo,dout;wire[23:0] out;
always #5 clk=~clk;
picture_settings_osd dut(clk,rst,1'b1,vs,de,rgb,active,selected,brightness,contrast,ho,vo,dout,out,volume_level);
integer x,y,pass,changed=0,ink=0,f;
reg[15:0] font[0:511];integer row;
task frame;begin
 @(negedge clk);vs=0;repeat(4)@(negedge clk);vs=1;repeat(4)@(negedge clk);
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)begin
   @(negedge clk);de=1;@(posedge clk);#1;
   if(!ho || !vo || !dout)$fatal(1,"OSD one-cycle sync alignment");
   if(!active || x<16 || x>255 || y<16 || y>155)begin
    if(out!==rgb)$fatal(1,"OSD changed pixels outside panel or while hidden x%0d y%0d",x,y);
   end else begin
    if(out!=rgb)changed=changed+1;
    if(out==24'hf5c784 || out==24'he8ddc9)ink=ink+1;
    if((x==16 || x==255 || y==16 || y==155) && out!==24'h806444)$fatal(1,"panel border not stable");
   end
   $fwrite(f,"%c%c%c",out[23:16],out[15:8],out[7:0]);
  end
  @(negedge clk);de=0;repeat(4)@(negedge clk);
 end
end endtask
initial begin
 $readmemh("D:/FPGA/competition/03_dev/oral_album_lyrics28/material/picture_settings_20261022/font.hex",font);
 #12;rst=0;
 for(row=0;row<512;row=row+1)
  if(dut.ui_font_row(row)!==font[row])$fatal(1,"OSD font row %0d differs",row);
 f=$fopen("settings_hidden.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 active=1;brightness=-64;contrast=4;
 f=$fopen("settings_brightness.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 selected=1;brightness=64;contrast=0;
 f=$fopen("settings_contrast.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 brightness=8;contrast=1;
 f=$fopen("settings_75.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 selected=2;brightness=0;contrast=2;volume_level=0;
 f=$fopen("settings_volume_0.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 volume_level=5;
 f=$fopen("settings_volume_50.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 volume_level=10;
 f=$fopen("settings_volume_100.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");frame;$fclose(f);
 if(changed<30000 || ink<1000)$fatal(1,"OSD has missing panel or unreadable glyphs");
 $display("PASS OSD: 512 font rows, +/-64/+08 and 50/75/150 contrast, volume 0/50/100%%, all three selections, 2150400 pixels bounded, hidden identity and one-cycle sync");$finish;
end
endmodule
