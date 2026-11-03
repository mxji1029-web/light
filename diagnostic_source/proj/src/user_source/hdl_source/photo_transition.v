// Optional curated geometry sequence. Style 0 preserves first-pair particles.
// Selection happens at SDRAM request time. This module never paints a backdrop.
module photo_transition #(
 parameter [15:0] FADE_FRAMES=16'd64,
 parameter MODE=1,
 parameter MULTI_TRANSITIONS=0,
 parameter AREA_UNIFORM=0
)(
 input clk,input rst,input hs_in,input vs_in,input de_in,input[23:0] rgb_in,
 input paused,
 input swap_toggle,input[1:0] new_idx,input[5:0] new_photo_id,
 output reg[5:0] shown_photo_id,output reg shown_toggle,
 output reg[1:0] read_idx,output reg busy,
 output hs_out,output vs_out,output de_out,output[23:0] rgb_out,
 output reg[1:0] reveal_idx,output reg[8:0] reveal_progress,output reg[3:0] reveal_style
);
localparam IDLE=2'd0,DISSOLVE=2'd1,HOLD=2'd2;
localparam [8:0] STEP=(256+(FADE_FRAMES>0?FADE_FRAMES:1)-1)/(FADE_FRAMES>0?FADE_FRAMES:1);
reg[1:0] state,swap_sync,idx_meta,idx_sync;
reg[5:0] id_meta,id_sync,target_id;
reg vs_d,swap_last,first_time,effect_used;
localparam integer FRAMES=FADE_FRAMES>0 ? FADE_FRAMES : 1;
localparam integer PHASE_BITS=FRAMES>1 ? $clog2(FRAMES+1) : 1;
reg [PHASE_BITS-1:0] phase_step;
wire [PHASE_BITS+6:0] phase_numerator=({1'b0,phase_step}+1'b1)<<6;
wire [6:0] ease_index=phase_numerator/FRAMES;

function [3:0] style_for_photo;
 input [5:0] photo;
 begin case(photo)
  6'd0:style_for_photo=4'd11;
  6'd1:style_for_photo=4'd0;
  6'd2:style_for_photo=4'd1;
  6'd3:style_for_photo=4'd2;
  6'd4:style_for_photo=4'd3;
  6'd5:style_for_photo=4'd4;
  6'd6:style_for_photo=4'd5;
  6'd7:style_for_photo=4'd6;
  6'd8:style_for_photo=4'd7;
  6'd9:style_for_photo=4'd8;
  6'd10:style_for_photo=4'd9;
  6'd11:style_for_photo=4'd10;
  6'd12:style_for_photo=4'd11;
  6'd13:style_for_photo=4'd0;
  6'd14:style_for_photo=4'd1;
  6'd15:style_for_photo=4'd2;
  6'd16:style_for_photo=4'd3;
  6'd17:style_for_photo=4'd4;
  6'd18:style_for_photo=4'd5;
  6'd19:style_for_photo=4'd6;
  6'd20:style_for_photo=4'd7;
  6'd21:style_for_photo=4'd8;
  6'd22:style_for_photo=4'd9;
  6'd23:style_for_photo=4'd10;
  6'd24:style_for_photo=4'd11;
  6'd25:style_for_photo=4'd0;
  6'd26:style_for_photo=4'd1;
  6'd27:style_for_photo=4'd2;
  6'd28:style_for_photo=4'd3;
  6'd29:style_for_photo=4'd4;
  6'd30:style_for_photo=4'd5;
  6'd31:style_for_photo=4'd6;
  6'd32:style_for_photo=4'd7;
  6'd33:style_for_photo=4'd8;
  6'd34:style_for_photo=4'd9;
  6'd35:style_for_photo=4'd10;
  6'd36:style_for_photo=4'd11;
  6'd37:style_for_photo=4'd0;
  6'd38:style_for_photo=4'd1;
  6'd39:style_for_photo=4'd2;
  6'd40:style_for_photo=4'd3;
  6'd41:style_for_photo=4'd4;
  6'd42:style_for_photo=4'd5;
  6'd43:style_for_photo=4'd6;
  6'd44:style_for_photo=4'd7;
  6'd45:style_for_photo=4'd8;
  6'd46:style_for_photo=4'd9;
  6'd47:style_for_photo=4'd10;
  6'd48:style_for_photo=4'd11;
  6'd49:style_for_photo=4'd0;
  6'd50:style_for_photo=4'd1;
  6'd51:style_for_photo=4'd2;
  6'd52:style_for_photo=4'd3;
  6'd53:style_for_photo=4'd4;
  6'd54:style_for_photo=4'd5;
  6'd55:style_for_photo=4'd6;
  6'd56:style_for_photo=4'd7;
  6'd57:style_for_photo=4'd8;
  6'd58:style_for_photo=4'd9;
  6'd59:style_for_photo=4'd10;
  6'd60:style_for_photo=4'd11;
  6'd61:style_for_photo=4'd0;
  6'd62:style_for_photo=4'd1;
  6'd63:style_for_photo=4'd2;
  default:style_for_photo=0;
 endcase end
endfunction
function [8:0] eased;
 input [6:0] t;
 begin case(t)
  7'd0:eased=9'd0;
  7'd1:eased=9'd0;
  7'd2:eased=9'd1;
  7'd3:eased=9'd2;
  7'd4:eased=9'd3;
  7'd5:eased=9'd4;
  7'd6:eased=9'd6;
  7'd7:eased=9'd9;
  7'd8:eased=9'd11;
  7'd9:eased=9'd14;
  7'd10:eased=9'd17;
  7'd11:eased=9'd20;
  7'd12:eased=9'd24;
  7'd13:eased=9'd27;
  7'd14:eased=9'd31;
  7'd15:eased=9'd36;
  7'd16:eased=9'd40;
  7'd17:eased=9'd45;
  7'd18:eased=9'd49;
  7'd19:eased=9'd54;
  7'd20:eased=9'd59;
  7'd21:eased=9'd65;
  7'd22:eased=9'd70;
  7'd23:eased=9'd75;
  7'd24:eased=9'd81;
  7'd25:eased=9'd87;
  7'd26:eased=9'd92;
  7'd27:eased=9'd98;
  7'd28:eased=9'd104;
  7'd29:eased=9'd110;
  7'd30:eased=9'd116;
  7'd31:eased=9'd122;
  7'd32:eased=9'd128;
  7'd33:eased=9'd134;
  7'd34:eased=9'd140;
  7'd35:eased=9'd146;
  7'd36:eased=9'd152;
  7'd37:eased=9'd158;
  7'd38:eased=9'd164;
  7'd39:eased=9'd169;
  7'd40:eased=9'd175;
  7'd41:eased=9'd181;
  7'd42:eased=9'd186;
  7'd43:eased=9'd191;
  7'd44:eased=9'd197;
  7'd45:eased=9'd202;
  7'd46:eased=9'd207;
  7'd47:eased=9'd211;
  7'd48:eased=9'd216;
  7'd49:eased=9'd220;
  7'd50:eased=9'd225;
  7'd51:eased=9'd229;
  7'd52:eased=9'd232;
  7'd53:eased=9'd236;
  7'd54:eased=9'd239;
  7'd55:eased=9'd242;
  7'd56:eased=9'd245;
  7'd57:eased=9'd247;
  7'd58:eased=9'd250;
  7'd59:eased=9'd252;
  7'd60:eased=9'd253;
  7'd61:eased=9'd254;
  7'd62:eased=9'd255;
  7'd63:eased=9'd255;
  7'd64:eased=9'd256;
  default:eased=256;
 endcase end
endfunction
// Inverse visible-area CDF of the unchanged 16x8 source-selection geometry.
// Seventeen anchors per style, interpolated with shifts/adds. Scalar case avoids
// consuming another block RAM; no per-pixel arithmetic or SDRAM reads are added.
function [8:0] area_anchor;
 input [3:0] style;input [4:0] anchor;
 begin case({style,anchor})
 9'd32:area_anchor=9'd0;
 9'd33:area_anchor=9'd10;
 9'd34:area_anchor=9'd23;
 9'd35:area_anchor=9'd35;
 9'd36:area_anchor=9'd51;
 9'd37:area_anchor=9'd69;
 9'd38:area_anchor=9'd89;
 9'd39:area_anchor=9'd111;
 9'd40:area_anchor=9'd133;
 9'd41:area_anchor=9'd155;
 9'd42:area_anchor=9'd177;
 9'd43:area_anchor=9'd198;
 9'd44:area_anchor=9'd216;
 9'd45:area_anchor=9'd230;
 9'd46:area_anchor=9'd244;
 9'd47:area_anchor=9'd255;
 9'd48:area_anchor=9'd256;
 9'd64:area_anchor=9'd0;
 9'd65:area_anchor=9'd23;
 9'd66:area_anchor=9'd41;
 9'd67:area_anchor=9'd59;
 9'd68:area_anchor=9'd76;
 9'd69:area_anchor=9'd90;
 9'd70:area_anchor=9'd104;
 9'd71:area_anchor=9'd118;
 9'd72:area_anchor=9'd130;
 9'd73:area_anchor=9'd143;
 9'd74:area_anchor=9'd156;
 9'd75:area_anchor=9'd170;
 9'd76:area_anchor=9'd185;
 9'd77:area_anchor=9'd203;
 9'd78:area_anchor=9'd219;
 9'd79:area_anchor=9'd236;
 9'd80:area_anchor=9'd256;
 9'd96:area_anchor=9'd0;
 9'd97:area_anchor=9'd19;
 9'd98:area_anchor=9'd41;
 9'd99:area_anchor=9'd62;
 9'd100:area_anchor=9'd79;
 9'd101:area_anchor=9'd97;
 9'd102:area_anchor=9'd112;
 9'd103:area_anchor=9'd129;
 9'd104:area_anchor=9'd142;
 9'd105:area_anchor=9'd155;
 9'd106:area_anchor=9'd169;
 9'd107:area_anchor=9'd183;
 9'd108:area_anchor=9'd196;
 9'd109:area_anchor=9'd209;
 9'd110:area_anchor=9'd223;
 9'd111:area_anchor=9'd238;
 9'd112:area_anchor=9'd256;
 9'd128:area_anchor=9'd0;
 9'd129:area_anchor=9'd3;
 9'd130:area_anchor=9'd11;
 9'd131:area_anchor=9'd24;
 9'd132:area_anchor=9'd40;
 9'd133:area_anchor=9'd59;
 9'd134:area_anchor=9'd81;
 9'd135:area_anchor=9'd104;
 9'd136:area_anchor=9'd128;
 9'd137:area_anchor=9'd152;
 9'd138:area_anchor=9'd175;
 9'd139:area_anchor=9'd197;
 9'd140:area_anchor=9'd216;
 9'd141:area_anchor=9'd233;
 9'd142:area_anchor=9'd246;
 9'd143:area_anchor=9'd253;
 9'd144:area_anchor=9'd256;
 9'd160:area_anchor=9'd0;
 9'd161:area_anchor=9'd10;
 9'd162:area_anchor=9'd23;
 9'd163:area_anchor=9'd36;
 9'd164:area_anchor=9'd52;
 9'd165:area_anchor=9'd70;
 9'd166:area_anchor=9'd90;
 9'd167:area_anchor=9'd111;
 9'd168:area_anchor=9'd134;
 9'd169:area_anchor=9'd157;
 9'd170:area_anchor=9'd179;
 9'd171:area_anchor=9'd198;
 9'd172:area_anchor=9'd216;
 9'd173:area_anchor=9'd232;
 9'd174:area_anchor=9'd244;
 9'd175:area_anchor=9'd255;
 9'd176:area_anchor=9'd256;
 9'd192:area_anchor=9'd0;
 9'd193:area_anchor=9'd27;
 9'd194:area_anchor=9'd43;
 9'd195:area_anchor=9'd61;
 9'd196:area_anchor=9'd76;
 9'd197:area_anchor=9'd92;
 9'd198:area_anchor=9'd107;
 9'd199:area_anchor=9'd122;
 9'd200:area_anchor=9'd133;
 9'd201:area_anchor=9'd145;
 9'd202:area_anchor=9'd159;
 9'd203:area_anchor=9'd173;
 9'd204:area_anchor=9'd189;
 9'd205:area_anchor=9'd205;
 9'd206:area_anchor=9'd221;
 9'd207:area_anchor=9'd241;
 9'd208:area_anchor=9'd256;
 9'd224:area_anchor=9'd0;
 9'd225:area_anchor=9'd19;
 9'd226:area_anchor=9'd38;
 9'd227:area_anchor=9'd59;
 9'd228:area_anchor=9'd75;
 9'd229:area_anchor=9'd91;
 9'd230:area_anchor=9'd107;
 9'd231:area_anchor=9'd120;
 9'd232:area_anchor=9'd134;
 9'd233:area_anchor=9'd150;
 9'd234:area_anchor=9'd158;
 9'd235:area_anchor=9'd168;
 9'd236:area_anchor=9'd179;
 9'd237:area_anchor=9'd192;
 9'd238:area_anchor=9'd208;
 9'd239:area_anchor=9'd224;
 9'd240:area_anchor=9'd256;
 9'd256:area_anchor=9'd0;
 9'd257:area_anchor=9'd9;
 9'd258:area_anchor=9'd21;
 9'd259:area_anchor=9'd33;
 9'd260:area_anchor=9'd47;
 9'd261:area_anchor=9'd64;
 9'd262:area_anchor=9'd82;
 9'd263:area_anchor=9'd102;
 9'd264:area_anchor=9'd123;
 9'd265:area_anchor=9'd143;
 9'd266:area_anchor=9'd163;
 9'd267:area_anchor=9'd182;
 9'd268:area_anchor=9'd198;
 9'd269:area_anchor=9'd212;
 9'd270:area_anchor=9'd224;
 9'd271:area_anchor=9'd237;
 9'd272:area_anchor=9'd256;
 9'd288:area_anchor=9'd0;
 9'd289:area_anchor=9'd18;
 9'd290:area_anchor=9'd33;
 9'd291:area_anchor=9'd47;
 9'd292:area_anchor=9'd60;
 9'd293:area_anchor=9'd73;
 9'd294:area_anchor=9'd87;
 9'd295:area_anchor=9'd101;
 9'd296:area_anchor=9'd115;
 9'd297:area_anchor=9'd127;
 9'd298:area_anchor=9'd144;
 9'd299:area_anchor=9'd159;
 9'd300:area_anchor=9'd176;
 9'd301:area_anchor=9'd194;
 9'd302:area_anchor=9'd215;
 9'd303:area_anchor=9'd237;
 9'd304:area_anchor=9'd256;
 9'd320:area_anchor=9'd0;
 9'd321:area_anchor=9'd42;
 9'd322:area_anchor=9'd64;
 9'd323:area_anchor=9'd88;
 9'd324:area_anchor=9'd110;
 9'd325:area_anchor=9'd131;
 9'd326:area_anchor=9'd151;
 9'd327:area_anchor=9'd169;
 9'd328:area_anchor=9'd185;
 9'd329:area_anchor=9'd201;
 9'd330:area_anchor=9'd215;
 9'd331:area_anchor=9'd226;
 9'd332:area_anchor=9'd236;
 9'd333:area_anchor=9'd245;
 9'd334:area_anchor=9'd253;
 9'd335:area_anchor=9'd256;
 9'd336:area_anchor=9'd256;
 9'd352:area_anchor=9'd0;
 9'd353:area_anchor=9'd2;
 9'd354:area_anchor=9'd10;
 9'd355:area_anchor=9'd22;
 9'd356:area_anchor=9'd37;
 9'd357:area_anchor=9'd55;
 9'd358:area_anchor=9'd75;
 9'd359:area_anchor=9'd97;
 9'd360:area_anchor=9'd120;
 9'd361:area_anchor=9'd144;
 9'd362:area_anchor=9'd170;
 9'd363:area_anchor=9'd193;
 9'd364:area_anchor=9'd214;
 9'd365:area_anchor=9'd231;
 9'd366:area_anchor=9'd245;
 9'd367:area_anchor=9'd253;
 9'd368:area_anchor=9'd256;
 default:area_anchor=9'd0;
 endcase end
endfunction
function [8:0] area_progress;
 input [3:0] style;input [6:0] t;
 reg [8:0] lo,hi,value;reg [10:0] delta_scaled;
 begin
  lo=area_anchor(style,{1'b0,t[5:2]});
  hi=area_anchor(style,{1'b0,t[5:2]}+5'd1);
  case(t[1:0])
   2'd0:delta_scaled=0;
   2'd1:delta_scaled=hi-lo;
   2'd2:delta_scaled=(hi-lo)<<1;
   default:delta_scaled=((hi-lo)<<1)+(hi-lo);
  endcase
  value=lo+((delta_scaled+11'd2)>>2);
  if(t>=64)area_progress=256;
  else area_progress=value;
 end
endfunction
wire event_pending=swap_sync[1]!=swap_last;
wire frame_edge=vs_d && !vs_in;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  reveal_style<=0;phase_step<=0;
  state<=IDLE;swap_sync<=0;swap_last<=0;vs_d<=1;
  idx_meta<=0;idx_sync<=0;id_meta<=0;id_sync<=0;target_id<=0;
  read_idx<=0;reveal_idx<=0;reveal_progress<=0;
  shown_photo_id<=0;shown_toggle<=0;busy<=0;first_time<=1;effect_used<=0;
 end else begin
  vs_d<=vs_in;swap_sync<={swap_sync[0],swap_toggle};
  idx_meta<=new_idx;idx_sync<=idx_meta;id_meta<=new_photo_id;id_sync<=id_meta;
  if(event_pending)busy<=1;
  if(frame_edge)case(state)
   IDLE:if(event_pending)begin
    swap_last<=swap_sync[1];busy<=1;first_time<=0;
    reveal_idx<=idx_sync;target_id<=id_sync;reveal_progress<=0;phase_step<=0;reveal_style<=style_for_photo(id_sync);
    if(!first_time && MODE==1 && read_idx!=idx_sync && (MULTI_TRANSITIONS || (!effect_used && shown_photo_id==0 && id_sync==1)))begin
     effect_used<=1;state<=DISSOLVE;
    end else begin
     read_idx<=idx_sync;shown_photo_id<=id_sync;shown_toggle<=~shown_toggle;state<=HOLD;
    end
   end
   DISSOLVE:if(paused!==1'b1)begin
    if(reveal_progress==256 && (!AREA_UNIFORM || !MULTI_TRANSITIONS || reveal_style==0 || phase_step>=FRAMES))begin
     read_idx<=reveal_idx;shown_photo_id<=target_id;shown_toggle<=~shown_toggle;
     reveal_progress<=0;state<=HOLD;
    end else if(MULTI_TRANSITIONS && reveal_style!=0)begin
     phase_step<=phase_step+1'b1;reveal_progress<=AREA_UNIFORM ? area_progress(reveal_style,ease_index) : eased(ease_index);
    end else if(reveal_progress>=256-STEP)reveal_progress<=256;
    else reveal_progress<=reveal_progress+STEP;
   end
   HOLD:begin busy<=0;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
end
assign hs_out=hs_in;
assign vs_out=vs_in;
assign de_out=de_in;
assign rgb_out=(!rst && de_in)?rgb_in:24'd0;
endmodule

