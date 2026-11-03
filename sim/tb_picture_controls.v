`timescale 1ns/1ps
module tb_picture_controls;
reg clk=0,fast_clk=0,rst=1,kn=1,ka=1,kp=1;
always #10 clk=~clk;always #5 fast_clk=~fast_clk;
wire nav_n,auto_n,mode,toggle,pulse;wire[1:0] selected;
wire signed[7:0] brightness;wire[2:0] contrast;
picture_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.HOLD_MS(20)) dut(
 .clk(clk),.rst(rst),.key_next_n(kn),.key_auto_n(ka),.key_pause_n(kp),
 .normal_next_n(nav_n),.normal_auto_n(auto_n),.settings_active(mode),.selected(selected),
 .brightness(brightness),.contrast_level(contrast),.pause_toggle(toggle));
picture_pause_event_sync bridge(fast_clk,rst,toggle,pulse);
integer pause_events=0,i;
always @(posedge fast_clk)if(!rst && pulse)pause_events=pause_events+1;
task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
task tap;input integer key;begin
 if(key==0)kn=0;else if(key==1)ka=0;else kp=0;
 tick(8);
 if(key==0)kn=1;else if(key==1)ka=1;else kp=1;
 tick(8);
end endtask
initial begin
 tick(4);rst=0;tick(5);
 if(mode || brightness!=0 || contrast!=2)$fatal(1,"bad default settings");
 kn=0;#1;if(nav_n!==0)$fatal(1,"normal next must preserve raw key");kn=1;
 kp=0;tick(1);kp=1;tick(10);if(pause_events!=0)$fatal(1,"bounce triggered pause");
 kp=0;tick(8);if(pause_events!=0)$fatal(1,"short press should wait for release");
 kp=1;tick(10);if(pause_events!=1 || !toggle)$fatal(1,"normal KEY3 short release must toggle playback once");
 kp=0;tick(35);if(!mode || pause_events!=1)$fatal(1,"long press must enter settings without pause");
 tick(35);if(!mode)$fatal(1,"held key repeatedly toggled settings");
 kp=1;tick(10);
 ka=0;tick(8);if(auto_n!==1 || brightness!=8)$fatal(1,"settings increase leaked navigation or failed");ka=1;tick(8);
 for(i=0;i<20;i=i+1)tap(1);
 if(brightness!=64)$fatal(1,"brightness upper clamp");
 for(i=0;i<30;i=i+1)tap(0);
 if(brightness!=-64)$fatal(1,"brightness lower clamp");
 tap(2);if(!selected || pause_events!=1)$fatal(1,"selection triggered audio pause");
 for(i=0;i<9;i=i+1)tap(1);
 if(contrast!=4)$fatal(1,"contrast upper clamp");
 for(i=0;i<9;i=i+1)tap(0);
 if(contrast!=0)$fatal(1,"contrast lower clamp");
 // Exit with a navigation key held: never expose a new falling edge on exit.
 kn=0;tick(8);kp=0;tick(35);
 if(mode || nav_n!==1 || pause_events!=1)$fatal(1,"exit released held next or toggled pause");
 kp=1;tick(10);if(nav_n!==1)$fatal(1,"navigation unblocked before all keys released");
 kn=1;tick(10);kn=0;#1;if(nav_n!==0)$fatal(1,"normal navigation did not recover");kn=1;
 repeat(3)tap(2);if(pause_events!=4 || toggle)$fatal(1,"normal short KEY3 failed playback toggles");
 rst=1;tick(3);rst=0;tick(5);
 if(mode || selected || brightness!=0 || contrast!=2)$fatal(1,"reset did not restore defaults");
 $display("PASS settings keys: normal KEY3 release toggles playback; long press/selection/limits/navigation guard preserved");$finish;
end
endmodule
