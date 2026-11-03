// Three existing active-low keys: long KEY3 selects a separate settings mode.
module picture_controls #(
 parameter integer CLK_HZ=25_000_000,DEBOUNCE_MS=20,HOLD_MS=1000,RESTORE_MS=300
)(input clk,input rst,input key_next_n,input key_auto_n,input key_pause_n,
 output normal_next_n,output normal_auto_n,
 output reg settings_active,output reg[1:0] selected,
 output reg signed[7:0] brightness,output reg[2:0] contrast_level,
 output reg pause_toggle,output reg[3:0] volume_level);
localparam integer DB_CYCLES=(CLK_HZ/1000)*DEBOUNCE_MS;
localparam integer HOLD_CYCLES=(CLK_HZ/1000)*HOLD_MS;
localparam integer DB_BITS=DB_CYCLES>1?$clog2(DB_CYCLES):1;
localparam integer HOLD_BITS=HOLD_CYCLES>1?$clog2(HOLD_CYCLES):1;
reg[2:0] key_meta,key_sync,stable,last_stable;
reg[DB_BITS-1:0] debounce_count[0:2];
reg[HOLD_BITS-1:0] hold_count;
localparam integer RESTORE_CYCLES=(CLK_HZ/1000)*RESTORE_MS;
localparam integer RESTORE_BITS=RESTORE_CYCLES>1?$clog2(RESTORE_CYCLES):1;
reg[RESTORE_BITS-1:0] restore_count;
reg restore_sent;
reg long_sent,nav_ready;
wire restore_due=settings_active && !stable[0] && !stable[1] && !restore_sent &&
                 restore_count==RESTORE_CYCLES-1;
wire[2:0] press=last_stable & ~stable;
wire pause_release=!last_stable[2] && stable[2];
integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  key_meta<=3'b111;key_sync<=3'b111;stable<=3'b111;
  for(i=0;i<3;i=i+1)debounce_count[i]<=0;
 end else begin
  key_meta<={key_pause_n,key_auto_n,key_next_n};key_sync<=key_meta;
  for(i=0;i<3;i=i+1)begin
   if(key_sync[i]==stable[i])debounce_count[i]<=0;
   else if(debounce_count[i]==DB_CYCLES-1)begin stable[i]<=key_sync[i];debounce_count[i]<=0;end
   else debounce_count[i]<=debounce_count[i]+1'b1;
  end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  last_stable<=3'b111;hold_count<=0;long_sent<=0;nav_ready<=1;restore_count<=0;restore_sent<=0;
  settings_active<=0;selected<=0;brightness<=0;contrast_level<=3'd2;pause_toggle<=0;volume_level<=4'd10;
 end else begin
  last_stable<=stable;
  // Only the settings menu accepts the restore chord. Releasing either key
  // cancels an incomplete hold; one event is allowed per stable full hold.
  if(!settings_active || stable[0] || stable[1])begin restore_count<=0;restore_sent<=0;end
  else if(!restore_sent)begin
   if(restore_due)restore_sent<=1;
   else restore_count<=restore_count+1'b1;
  end
  if(!settings_active && stable==3'b111 && key_sync==3'b111)nav_ready<=1;
  if(stable[2])begin hold_count<=0;long_sent<=0;end
  else if(!long_sent)begin
   if(hold_count==HOLD_CYCLES-1)begin
    settings_active<=~settings_active;long_sent<=1;nav_ready<=0;
   end else hold_count<=hold_count+1'b1;
  end
  if(pause_release && !long_sent)begin
   if(settings_active)selected<=selected==2 ? 2'd0 : selected+2'd1;
   else pause_toggle<=~pause_toggle;
  end
  if(settings_active)begin
   if(restore_due)begin brightness<=0;contrast_level<=3'd2;end
   else if(press[0] && !press[1])begin
    if(selected==2)begin if(volume_level>0)volume_level<=volume_level-1'b1;end
    else if(selected==1)begin if(contrast_level>0)contrast_level<=contrast_level-1'b1;end
    else if(brightness> -8'sd64)brightness<=brightness-8'sd8;
   end else if(press[1] && !press[0])begin
    if(selected==2)begin if(volume_level<10)volume_level<=volume_level+1'b1;end
    else if(selected==1)begin if(contrast_level<4)contrast_level<=contrast_level+1'b1;end
    else if(brightness<8'sd64)brightness<=brightness+8'sd8;
   end
  end
 end
end
// Original navigation debounce remains in sd_card_bmp; avoid a second delay.
// Re-opening is allowed only after every key has been released after mode exit.
assign normal_next_n=(!settings_active && nav_ready)?key_next_n:1'b1;
assign normal_auto_n=(!settings_active && nav_ready)?key_auto_n:1'b1;
endmodule

// Human-rate events cross video_clk -> 50MHz without relying on pulse width.
module picture_pause_event_sync(input clk,input rst,input async_toggle,output pulse);
reg[1:0] sync;reg previous;
always @(posedge clk or posedge rst)
 if(rst)begin sync<=0;previous<=0;end
 else begin sync<={sync[0],async_toggle};previous<=sync[1];end
assign pulse=sync[1]^previous;
endmodule
