`timescale 1ns/1ps
module tb_controls_volume;
reg clk=0,rst=1,kn=1,ka=1,kp=1;always #5 clk=~clk;
wire nav,auto_n,active,toggle;wire[1:0] selected;wire[3:0] volume;
wire signed[7:0] brightness;wire[2:0] contrast;
picture_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.HOLD_MS(20),.RESTORE_MS(30)) dut(
 .clk(clk),.rst(rst),.key_next_n(kn),.key_auto_n(ka),.key_pause_n(kp),
 .normal_next_n(nav),.normal_auto_n(auto_n),.settings_active(active),.selected(selected),
 .brightness(brightness),.contrast_level(contrast),.pause_toggle(toggle),.volume_level(volume));
task ticks;input integer n;begin repeat(n)@(negedge clk);end endtask
task tap;input integer key;begin
 if(key==0)kn=0;else if(key==1)ka=0;else kp=0;
 ticks(8);kn=1;ka=1;kp=1;ticks(8);
end endtask
task long_key3;begin kp=0;ticks(35);kp=1;ticks(10);end endtask
integer i;
initial begin
 ticks(4);rst=0;ticks(5);
 if(active || selected!=0 || volume!=10 || toggle)$fatal(1,"initial defaults changed");
 kp=0;ticks(1);kp=1;ticks(10);if(toggle)$fatal(1,"bounce toggled playback");
 tap(2);if(!toggle)$fatal(1,"normal KEY3 did not start playback");
 long_key3;if(!active || !toggle)$fatal(1,"long press changed transport");
 tap(1);if(brightness!=8)$fatal(1,"brightness item changed");
 tap(2);if(selected!=1)$fatal(1,"second item not contrast");
 tap(1);if(contrast!=3)$fatal(1,"contrast item changed");
 tap(2);if(selected!=2)$fatal(1,"third menu item missing: selected=%0d",selected);
 for(i=0;i<13;i=i+1)tap(0);
 if(volume!=0 || brightness!=8 || contrast!=3 || !toggle)$fatal(1,"volume lower clamp/selection isolation");
 for(i=0;i<13;i=i+1)tap(1);
 if(volume!=10 || !toggle)$fatal(1,"volume upper clamp or transport changed");
 repeat(3)tap(0);if(volume!=7)$fatal(1,"volume steps not10 percent");
 kn=0;ka=0;ticks(45);kn=1;ka=1;ticks(10);
 if(brightness!=0 || contrast!=2 || volume!=7 || selected!=2)$fatal(1,"picture restore changed volume/menu");
 tap(2);if(selected!=0)$fatal(1,"menu did not wrap to brightness");
 // Preserve release protection when leaving menu with a held navigation key.
 kn=0;ticks(8);kp=0;ticks(35);
 if(active || !nav || !toggle)$fatal(1,"exit leaked navigation or paused playback");
 kp=1;ticks(10);if(!nav)$fatal(1,"held nav leaked on exit");
 kn=1;ticks(10);kn=0;#1;if(nav)$fatal(1,"normal navigation not restored");kn=1;
 tap(2);if(toggle)$fatal(1,"normal KEY3 did not pause");tap(2);if(!toggle)$fatal(1,"normal KEY3 did not resume");
 rst=1;ticks(3);rst=0;ticks(5);
 if(volume!=10 || selected!=0 || active || toggle)$fatal(1,"reset defaults");
 $display("PASS controls: third volume item0..10, clamps, menu wrap, picture-only restore, KEY3 semantics and held-nav guard");$finish;
end
initial begin #100000;$fatal(1,"controls timeout");end
endmodule
