`timescale 1ns/1ps
// Temporary, frame-atomic status HUD. Coordinates are active-video pixels.
// Two rows in x448..623/y16..63; all geometry and seven-segment numerals are
// combinational dynamic ink plus synchronous fixed-icon ROM; no frame memory.
module playback_status_osd #(parameter SHOW_FRAMES=120)(
 input clk,input rst,input hs,input vs,input de,input[23:0] rgb,
 input display_ready,input paused,input auto_play,input[5:0] shown_photo_id,
 input[6:0] photo_count,input[3:0] volume_level,
 output reg hs_out,output reg vs_out,output reg de_out,output reg[23:0] rgb_out
);
localparam TIMER_WIDTH=SHOW_FRAMES<2?1:$clog2(SHOW_FRAMES+1);
localparam[23:0] GOLD=24'hf5c784,IVORY=24'he8ddc9,EDGE=24'h806444,
                DARK=24'h1c252c,MUTED=24'h423c34;
reg vs_d,de_d,ready_q,paused_q,auto_q;
reg[5:0] id_q;reg[6:0] count_q;reg[3:0] volume_q;
reg[TIMER_WIDTH-1:0] frames_left;
reg[9:0] x_count,y_count;
wire[9:0] pixel_x=de_d?x_count:10'd0;
wire[3:0] bounded_volume=volume_level>10?4'd10:volume_level;
// Page changes update the displayed number without opening/extending the HUD.
wire event_changed=!ready_q || paused!=paused_q || auto_play!=auto_q ||
                   bounded_volume!=volume_q;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  vs_d<=1;ready_q<=0;paused_q<=0;auto_q<=0;id_q<=0;count_q<=0;
  volume_q<=10;frames_left<=0;
 end else begin
  vs_d<=vs;
  if(vs && !vs_d)begin
   ready_q<=display_ready;paused_q<=paused;auto_q<=auto_play;id_q<=shown_photo_id;
   count_q<=photo_count>64?7'd64:photo_count;volume_q<=bounded_volume;
   if(!display_ready)frames_left<=0;
   else if(event_changed)frames_left<=SHOW_FRAMES;
   else if(frames_left!=0)frames_left<=frames_left-1'b1;
  end
 end
end
function[3:0] tens;
 input[6:0] value;
 begin tens=value>=60?6:value>=50?5:value>=40?4:value>=30?3:value>=20?2:value>=10?1:0;end
endfunction
function[3:0] ones;
 input[6:0] value;reg[3:0] t;reg[6:0] ten_t;
 begin t=tens(value);ten_t={t,3'b0}+{2'b0,t,1'b0};ones=value-ten_t;end
endfunction
function digit_pixel;
 input[3:0] number;input[2:0] x;input[3:0] y;reg[6:0] seg;
 begin
  case(number)
   0:seg=7'h7e;1:seg=7'h30;2:seg=7'h6d;3:seg=7'h79;4:seg=7'h33;
   5:seg=7'h5b;6:seg=7'h5f;7:seg=7'h70;8:seg=7'h7f;9:seg=7'h7b;
   default:seg=0;
  endcase
  digit_pixel=(seg[6] && x>=1 && x<=6 && y>=0 && y<=1) ||
              (seg[5] && x>=6 && x<=7 && y>=1 && y<=6) ||
              (seg[4] && x>=6 && x<=7 && y>=7 && y<=12) ||
              (seg[3] && x>=1 && x<=6 && y>=12 && y<=13) ||
              (seg[2] && x>=0 && x<=1 && y>=7 && y<=12) ||
              (seg[1] && x>=0 && x<=1 && y>=1 && y<=6) ||
              (seg[0] && x>=1 && x<=6 && y>=6 && y<=7);
 end
endfunction
wire[6:0] shown_number={1'b0,id_q}+7'd1;
// Panel-local arithmetic is sufficient: x0..175/y0..47. All ink is masked by
// panel below, so modular coordinates outside that rectangle are unobservable.
wire[7:0] hx=pixel_x[7:0]-8'd192;
wire[5:0] hy=y_count[5:0]-6'd16;
wire[7:0] hsum=hx+{2'b0,hy};
// The raster visits one digit at a time. Share one seven-segment decoder;
// only subtract local 3/4-bit coordinates after selecting its 8x14 rectangle.
// The previous parallel integer-coordinate decoders exceeded MSlice packing.
reg digit_on;reg[3:0] digit_value,digit_y;reg[2:0] digit_x;
always @* begin
 digit_on=0;digit_value=0;digit_x=0;digit_y=0;
 if(hy>=6'd7 && hy<=6'd20)begin
  digit_y=hy[3:0]-4'd7;
  if(hx>=8'd78 && hx<=8'd85 && shown_number>=10)begin
   digit_on=1;digit_value=tens(shown_number);digit_x=hx[2:0]-3'd6;
  end else if(hx>=8'd88 && hx<=8'd95)begin
   digit_on=1;digit_value=ones(shown_number);digit_x=hx[2:0];
  end else if(hx>=8'd118 && hx<=8'd125 && count_q>=10)begin
   digit_on=1;digit_value=tens(count_q);digit_x=hx[2:0]-3'd6;
  end else if(hx>=8'd128 && hx<=8'd135 && count_q!=0)begin
   digit_on=1;digit_value=ones(count_q);digit_x=hx[2:0];
  end
 end else if(hy>=6'd29 && hy<=6'd42)begin
  digit_y=hy[3:0]-4'd13;
  if(hx>=8'd124 && hx<=8'd131 && volume_q==10)begin
   digit_on=1;digit_value=1;digit_x=hx[2:0]-3'd4;
  end else if(hx>=8'd134 && hx<=8'd141 && volume_q!=0)begin
   digit_on=1;digit_value=volume_q==10?4'd0:volume_q;digit_x=hx[2:0]-3'd6;
  end else if(hx>=8'd144 && hx<=8'd151)begin
   digit_on=1;digit_value=0;digit_x=hx[2:0];
  end
 end
end
wire digits_ink=digit_on && digit_pixel(digit_value,digit_x,digit_y);
wire unknown_total_ink=count_q==0 &&
 ((hx>=8'd118 && hx<=8'd125 || hx>=8'd128 && hx<=8'd135) && hy>=6'd13 && hy<=6'd14);
wire slash_ink=hx>=8'd100 && hx<=8'd110 && hy>=6'd8 && hy<=6'd18 && hsum==8'd118;
wire percent_ink=(hx>=8'd156 && hx<=8'd159 && hy>=6'd31 && hy<=6'd34 &&
                 (hx==8'd156 || hx==8'd159 || hy==6'd31 || hy==6'd34)) ||
                (hx>=8'd163 && hx<=8'd166 && hy>=6'd38 && hy<=6'd41 &&
                 (hx==8'd163 || hx==8'd166 || hy==6'd38 || hy==6'd41)) ||
                (hx>=8'd156 && hx<=8'd166 && hy>=6'd31 && hy<=6'd41 && hsum==8'd197);
wire[7:0] bar_x=hx-8'd30;
wire bar_area=hx>=8'd30 && hx<=8'd107 && hy>=6'd31 && hy<=6'd40 && bar_x[2:0]<6;
wire bar_filled=bar_x[6:3]<volume_q;
wire visible=ready_q && frames_left!=0;
wire panel=visible && de && pixel_x>=448 && pixel_x<=623 && y_count>=16 && y_count<=63;
wire border=hx==8'd0 || hx==8'd175 || hy==6'd0 || hy==6'd47;
wire divider=hx>=8'd8 && hx<=8'd167 && hy==6'd24;
wire white_ink=digits_ink || unknown_total_ink || slash_ink || percent_ink;
// The ROM and metadata sample the same pixel. Final RGB is selected solely
// from these registered values, preserving the original one-clock pipeline.
wire[5:0] icon_mask;
playback_status_icon_rom icons(.clk(clk),.address({hy,hx[6:0]}),.mask(icon_mask));
reg[23:0] base_rgb_q;
reg icon_eligible_q,icon_paused_q,icon_auto_q,icon_muted_q,base_dark_q;
wire icon_gold=(icon_paused_q?icon_mask[1]:icon_mask[0]) || icon_mask[3] ||
               (icon_muted_q?icon_mask[5]:icon_mask[4]) || (icon_auto_q && icon_mask[2]);
always @(posedge clk or posedge rst)begin
 if(rst)begin
  x_count<=0;y_count<=0;de_d<=0;hs_out<=1;vs_out<=1;de_out<=0;base_rgb_q<=0;
  icon_eligible_q<=0;icon_paused_q<=0;icon_auto_q<=0;icon_muted_q<=0;base_dark_q<=0;
 end else begin
  de_d<=de;
  if(!vs)begin x_count<=0;y_count<=0;end
  else if(de)x_count<=pixel_x+10'd1;
  else if(de_d)begin x_count<=0;y_count<=y_count+10'd1;end
  hs_out<=hs;vs_out<=vs;de_out<=de;
  icon_eligible_q<=panel && !border && !hx[7];
  icon_paused_q<=paused_q;icon_auto_q<=auto_q;icon_muted_q<=volume_q==0;
  base_dark_q<=panel && !border && !white_ink && !bar_area && !divider;
  if(!panel)base_rgb_q<=rgb;
  else if(border)base_rgb_q<=EDGE;
  else if(white_ink)base_rgb_q<=IVORY;
  else if(bar_area)base_rgb_q<=bar_filled?GOLD:MUTED;
  else if(divider)base_rgb_q<=MUTED;
  else base_rgb_q<=DARK;
 end
end
always @* begin
 rgb_out=base_rgb_q;
 if(icon_eligible_q && icon_gold)rgb_out=GOLD;
 else if(icon_eligible_q && !icon_auto_q && icon_mask[2] && base_dark_q)rgb_out=MUTED;
end
endmodule

// Six fixed icon planes: play,pause,auto,photo,speaker-on,speaker-muted.
// 48x128 pixels occupy three 2048x16 BRAM32K banks. High ten bits are zero.
module playback_status_icon_rom(input clk,input[12:0] address,output[5:0] mask);
function[15:0] icon_word;input[12:0] address;begin
 case(address)
 13'd682:icon_word=16'h0004;
 13'd811:icon_word=16'h0004;
 13'd940:icon_word=16'h0004;
 13'd1032:icon_word=16'h0003;
 13'd1033:icon_word=16'h0002;
 13'd1034:icon_word=16'h0002;
 13'd1035:icon_word=16'h0002;
 13'd1040:icon_word=16'h0002;
 13'd1041:icon_word=16'h0002;
 13'd1042:icon_word=16'h0002;
 13'd1043:icon_word=16'h0002;
 13'd1069:icon_word=16'h0004;
 13'd1080:icon_word=16'h0008;
 13'd1081:icon_word=16'h0008;
 13'd1082:icon_word=16'h0008;
 13'd1083:icon_word=16'h0008;
 13'd1084:icon_word=16'h0008;
 13'd1085:icon_word=16'h0008;
 13'd1086:icon_word=16'h0008;
 13'd1087:icon_word=16'h0008;
 13'd1088:icon_word=16'h0008;
 13'd1089:icon_word=16'h0008;
 13'd1090:icon_word=16'h0008;
 13'd1091:icon_word=16'h0008;
 13'd1092:icon_word=16'h0008;
 13'd1093:icon_word=16'h0008;
 13'd1160:icon_word=16'h0003;
 13'd1161:icon_word=16'h0003;
 13'd1162:icon_word=16'h0003;
 13'd1163:icon_word=16'h0002;
 13'd1168:icon_word=16'h0002;
 13'd1169:icon_word=16'h0002;
 13'd1170:icon_word=16'h0002;
 13'd1171:icon_word=16'h0002;
 13'd1184:icon_word=16'h0004;
 13'd1185:icon_word=16'h0004;
 13'd1186:icon_word=16'h0004;
 13'd1187:icon_word=16'h0004;
 13'd1188:icon_word=16'h0004;
 13'd1189:icon_word=16'h0004;
 13'd1190:icon_word=16'h0004;
 13'd1191:icon_word=16'h0004;
 13'd1192:icon_word=16'h0004;
 13'd1193:icon_word=16'h0004;
 13'd1194:icon_word=16'h0004;
 13'd1195:icon_word=16'h0004;
 13'd1196:icon_word=16'h0004;
 13'd1197:icon_word=16'h0004;
 13'd1198:icon_word=16'h0004;
 13'd1208:icon_word=16'h0008;
 13'd1221:icon_word=16'h0008;
 13'd1288:icon_word=16'h0003;
 13'd1289:icon_word=16'h0003;
 13'd1290:icon_word=16'h0003;
 13'd1291:icon_word=16'h0003;
 13'd1292:icon_word=16'h0001;
 13'd1296:icon_word=16'h0002;
 13'd1297:icon_word=16'h0002;
 13'd1298:icon_word=16'h0002;
 13'd1299:icon_word=16'h0002;
 13'd1325:icon_word=16'h0004;
 13'd1336:icon_word=16'h0008;
 13'd1349:icon_word=16'h0008;
 13'd1416:icon_word=16'h0003;
 13'd1417:icon_word=16'h0003;
 13'd1418:icon_word=16'h0003;
 13'd1419:icon_word=16'h0003;
 13'd1420:icon_word=16'h0001;
 13'd1421:icon_word=16'h0001;
 13'd1422:icon_word=16'h0001;
 13'd1424:icon_word=16'h0002;
 13'd1425:icon_word=16'h0002;
 13'd1426:icon_word=16'h0002;
 13'd1427:icon_word=16'h0002;
 13'd1452:icon_word=16'h0004;
 13'd1464:icon_word=16'h0008;
 13'd1467:icon_word=16'h0008;
 13'd1477:icon_word=16'h0008;
 13'd1544:icon_word=16'h0003;
 13'd1545:icon_word=16'h0003;
 13'd1546:icon_word=16'h0003;
 13'd1547:icon_word=16'h0003;
 13'd1548:icon_word=16'h0001;
 13'd1549:icon_word=16'h0001;
 13'd1550:icon_word=16'h0001;
 13'd1551:icon_word=16'h0001;
 13'd1552:icon_word=16'h0003;
 13'd1553:icon_word=16'h0002;
 13'd1554:icon_word=16'h0002;
 13'd1555:icon_word=16'h0002;
 13'd1579:icon_word=16'h0004;
 13'd1592:icon_word=16'h0008;
 13'd1605:icon_word=16'h0008;
 13'd1672:icon_word=16'h0003;
 13'd1673:icon_word=16'h0003;
 13'd1674:icon_word=16'h0003;
 13'd1675:icon_word=16'h0003;
 13'd1676:icon_word=16'h0001;
 13'd1677:icon_word=16'h0001;
 13'd1678:icon_word=16'h0001;
 13'd1679:icon_word=16'h0001;
 13'd1680:icon_word=16'h0003;
 13'd1681:icon_word=16'h0003;
 13'd1682:icon_word=16'h0003;
 13'd1683:icon_word=16'h0002;
 13'd1706:icon_word=16'h0004;
 13'd1720:icon_word=16'h0008;
 13'd1726:icon_word=16'h0008;
 13'd1730:icon_word=16'h0008;
 13'd1733:icon_word=16'h0008;
 13'd1800:icon_word=16'h0003;
 13'd1801:icon_word=16'h0003;
 13'd1802:icon_word=16'h0003;
 13'd1803:icon_word=16'h0003;
 13'd1804:icon_word=16'h0001;
 13'd1805:icon_word=16'h0001;
 13'd1806:icon_word=16'h0001;
 13'd1807:icon_word=16'h0001;
 13'd1808:icon_word=16'h0003;
 13'd1809:icon_word=16'h0003;
 13'd1810:icon_word=16'h0003;
 13'd1811:icon_word=16'h0002;
 13'd1826:icon_word=16'h0004;
 13'd1848:icon_word=16'h0008;
 13'd1853:icon_word=16'h0008;
 13'd1855:icon_word=16'h0008;
 13'd1857:icon_word=16'h0008;
 13'd1859:icon_word=16'h0008;
 13'd1861:icon_word=16'h0008;
 13'd1928:icon_word=16'h0003;
 13'd1929:icon_word=16'h0003;
 13'd1930:icon_word=16'h0003;
 13'd1931:icon_word=16'h0003;
 13'd1932:icon_word=16'h0001;
 13'd1933:icon_word=16'h0001;
 13'd1934:icon_word=16'h0001;
 13'd1935:icon_word=16'h0001;
 13'd1936:icon_word=16'h0003;
 13'd1937:icon_word=16'h0002;
 13'd1938:icon_word=16'h0002;
 13'd1939:icon_word=16'h0002;
 13'd1953:icon_word=16'h0004;
 13'd1976:icon_word=16'h0008;
 13'd1980:icon_word=16'h0008;
 13'd1984:icon_word=16'h0008;
 13'd1988:icon_word=16'h0008;
 13'd1989:icon_word=16'h0008;
 13'd2056:icon_word=16'h0003;
 13'd2057:icon_word=16'h0003;
 13'd2058:icon_word=16'h0003;
 13'd2059:icon_word=16'h0003;
 13'd2060:icon_word=16'h0001;
 13'd2061:icon_word=16'h0001;
 13'd2062:icon_word=16'h0001;
 13'd2064:icon_word=16'h0002;
 13'd2065:icon_word=16'h0002;
 13'd2066:icon_word=16'h0002;
 13'd2067:icon_word=16'h0002;
 13'd2080:icon_word=16'h0004;
 13'd2104:icon_word=16'h0008;
 13'd2107:icon_word=16'h0008;
 13'd2113:icon_word=16'h0008;
 13'd2117:icon_word=16'h0008;
 13'd2184:icon_word=16'h0003;
 13'd2185:icon_word=16'h0003;
 13'd2186:icon_word=16'h0003;
 13'd2187:icon_word=16'h0003;
 13'd2188:icon_word=16'h0001;
 13'd2192:icon_word=16'h0002;
 13'd2193:icon_word=16'h0002;
 13'd2194:icon_word=16'h0002;
 13'd2195:icon_word=16'h0002;
 13'd2207:icon_word=16'h0004;
 13'd2232:icon_word=16'h0008;
 13'd2234:icon_word=16'h0008;
 13'd2242:icon_word=16'h0008;
 13'd2245:icon_word=16'h0008;
 13'd2312:icon_word=16'h0003;
 13'd2313:icon_word=16'h0003;
 13'd2314:icon_word=16'h0003;
 13'd2315:icon_word=16'h0002;
 13'd2320:icon_word=16'h0002;
 13'd2321:icon_word=16'h0002;
 13'd2322:icon_word=16'h0002;
 13'd2323:icon_word=16'h0002;
 13'd2334:icon_word=16'h0004;
 13'd2335:icon_word=16'h0004;
 13'd2336:icon_word=16'h0004;
 13'd2337:icon_word=16'h0004;
 13'd2338:icon_word=16'h0004;
 13'd2339:icon_word=16'h0004;
 13'd2340:icon_word=16'h0004;
 13'd2341:icon_word=16'h0004;
 13'd2342:icon_word=16'h0004;
 13'd2343:icon_word=16'h0004;
 13'd2344:icon_word=16'h0004;
 13'd2345:icon_word=16'h0004;
 13'd2346:icon_word=16'h0004;
 13'd2347:icon_word=16'h0004;
 13'd2348:icon_word=16'h0004;
 13'd2360:icon_word=16'h0008;
 13'd2373:icon_word=16'h0008;
 13'd2440:icon_word=16'h0003;
 13'd2441:icon_word=16'h0002;
 13'd2442:icon_word=16'h0002;
 13'd2443:icon_word=16'h0002;
 13'd2448:icon_word=16'h0002;
 13'd2449:icon_word=16'h0002;
 13'd2450:icon_word=16'h0002;
 13'd2451:icon_word=16'h0002;
 13'd2463:icon_word=16'h0004;
 13'd2488:icon_word=16'h0008;
 13'd2489:icon_word=16'h0008;
 13'd2490:icon_word=16'h0008;
 13'd2491:icon_word=16'h0008;
 13'd2492:icon_word=16'h0008;
 13'd2493:icon_word=16'h0008;
 13'd2494:icon_word=16'h0008;
 13'd2495:icon_word=16'h0008;
 13'd2496:icon_word=16'h0008;
 13'd2497:icon_word=16'h0008;
 13'd2498:icon_word=16'h0008;
 13'd2499:icon_word=16'h0008;
 13'd2500:icon_word=16'h0008;
 13'd2501:icon_word=16'h0008;
 13'd2592:icon_word=16'h0004;
 13'd2721:icon_word=16'h0004;
 13'd2850:icon_word=16'h0004;
 13'd3601:icon_word=16'h0030;
 13'd3728:icon_word=16'h0030;
 13'd3729:icon_word=16'h0030;
 13'd3855:icon_word=16'h0030;
 13'd3856:icon_word=16'h0030;
 13'd3857:icon_word=16'h0030;
 13'd3864:icon_word=16'h0010;
 13'd3982:icon_word=16'h0030;
 13'd3983:icon_word=16'h0030;
 13'd3984:icon_word=16'h0030;
 13'd3985:icon_word=16'h0030;
 13'd3992:icon_word=16'h0010;
 13'd4109:icon_word=16'h0030;
 13'd4110:icon_word=16'h0030;
 13'd4111:icon_word=16'h0030;
 13'd4112:icon_word=16'h0030;
 13'd4113:icon_word=16'h0030;
 13'd4116:icon_word=16'h0020;
 13'd4117:icon_word=16'h0010;
 13'd4120:icon_word=16'h0010;
 13'd4122:icon_word=16'h0020;
 13'd4232:icon_word=16'h0030;
 13'd4233:icon_word=16'h0030;
 13'd4234:icon_word=16'h0030;
 13'd4235:icon_word=16'h0030;
 13'd4236:icon_word=16'h0030;
 13'd4237:icon_word=16'h0030;
 13'd4238:icon_word=16'h0030;
 13'd4239:icon_word=16'h0030;
 13'd4240:icon_word=16'h0030;
 13'd4241:icon_word=16'h0030;
 13'd4245:icon_word=16'h0030;
 13'd4248:icon_word=16'h0010;
 13'd4249:icon_word=16'h0020;
 13'd4360:icon_word=16'h0030;
 13'd4361:icon_word=16'h0030;
 13'd4362:icon_word=16'h0030;
 13'd4363:icon_word=16'h0030;
 13'd4364:icon_word=16'h0030;
 13'd4365:icon_word=16'h0030;
 13'd4366:icon_word=16'h0030;
 13'd4367:icon_word=16'h0030;
 13'd4368:icon_word=16'h0030;
 13'd4369:icon_word=16'h0030;
 13'd4373:icon_word=16'h0010;
 13'd4374:icon_word=16'h0020;
 13'd4376:icon_word=16'h0030;
 13'd4488:icon_word=16'h0030;
 13'd4489:icon_word=16'h0030;
 13'd4490:icon_word=16'h0030;
 13'd4491:icon_word=16'h0030;
 13'd4492:icon_word=16'h0030;
 13'd4493:icon_word=16'h0030;
 13'd4494:icon_word=16'h0030;
 13'd4495:icon_word=16'h0030;
 13'd4496:icon_word=16'h0030;
 13'd4497:icon_word=16'h0030;
 13'd4501:icon_word=16'h0010;
 13'd4503:icon_word=16'h0020;
 13'd4504:icon_word=16'h0010;
 13'd4616:icon_word=16'h0030;
 13'd4617:icon_word=16'h0030;
 13'd4618:icon_word=16'h0030;
 13'd4619:icon_word=16'h0030;
 13'd4620:icon_word=16'h0030;
 13'd4621:icon_word=16'h0030;
 13'd4622:icon_word=16'h0030;
 13'd4623:icon_word=16'h0030;
 13'd4624:icon_word=16'h0030;
 13'd4625:icon_word=16'h0030;
 13'd4629:icon_word=16'h0010;
 13'd4630:icon_word=16'h0020;
 13'd4632:icon_word=16'h0030;
 13'd4744:icon_word=16'h0030;
 13'd4745:icon_word=16'h0030;
 13'd4746:icon_word=16'h0030;
 13'd4747:icon_word=16'h0030;
 13'd4748:icon_word=16'h0030;
 13'd4749:icon_word=16'h0030;
 13'd4750:icon_word=16'h0030;
 13'd4751:icon_word=16'h0030;
 13'd4752:icon_word=16'h0030;
 13'd4753:icon_word=16'h0030;
 13'd4757:icon_word=16'h0030;
 13'd4760:icon_word=16'h0010;
 13'd4761:icon_word=16'h0020;
 13'd4872:icon_word=16'h0030;
 13'd4873:icon_word=16'h0030;
 13'd4874:icon_word=16'h0030;
 13'd4875:icon_word=16'h0030;
 13'd4876:icon_word=16'h0030;
 13'd4877:icon_word=16'h0030;
 13'd4878:icon_word=16'h0030;
 13'd4879:icon_word=16'h0030;
 13'd4880:icon_word=16'h0030;
 13'd4881:icon_word=16'h0030;
 13'd4884:icon_word=16'h0020;
 13'd4885:icon_word=16'h0010;
 13'd4888:icon_word=16'h0010;
 13'd4890:icon_word=16'h0020;
 13'd5005:icon_word=16'h0030;
 13'd5006:icon_word=16'h0030;
 13'd5007:icon_word=16'h0030;
 13'd5008:icon_word=16'h0030;
 13'd5009:icon_word=16'h0030;
 13'd5013:icon_word=16'h0010;
 13'd5016:icon_word=16'h0010;
 13'd5134:icon_word=16'h0030;
 13'd5135:icon_word=16'h0030;
 13'd5136:icon_word=16'h0030;
 13'd5137:icon_word=16'h0030;
 13'd5144:icon_word=16'h0010;
 13'd5263:icon_word=16'h0030;
 13'd5264:icon_word=16'h0030;
 13'd5265:icon_word=16'h0030;
 13'd5272:icon_word=16'h0010;
 13'd5392:icon_word=16'h0030;
 13'd5393:icon_word=16'h0030;
 13'd5521:icon_word=16'h0030;
 default:icon_word=16'd0;
 endcase
end
endfunction

`ifdef __ICARUS__
reg[5:0] sim_mask;
always @(posedge clk)sim_mask<=icon_word(address);
assign mask=sim_mask;
`else
function[255:0] icon_init_block;
 input integer bank,block_index;integer row;
 begin
  for(row=0;row<16;row=row+1)
   icon_init_block[row*16+:16]=icon_word(bank*2048+block_index*16+row);
 end
endfunction
wire[15:0] bank_word[0:2];
reg[1:0] bank_q;
always @(posedge clk)bank_q<=address[12:11];
assign mask=bank_q==0?bank_word[0][5:0]:bank_q==1?bank_word[1][5:0]:
            bank_q==2?bank_word[2][5:0]:6'd0;
genvar bank;
generate for(bank=0;bank<3;bank=bank+1)begin:icon_bank
EG_PHY_BRAM32K #(
 .MODE("SP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.SRMODE("SYNC"),
 .CSAMUX("SIG"),.CSBMUX("SIG"),.OCEAMUX("SIG"),.OCEBMUX("SIG"),
 .RSTAMUX("SIG"),.RSTBMUX("SIG"),.CLKAMUX("SIG"),.CLKBMUX("SIG"),
 .WEAMUX("SIG"),.WEBMUX("SIG"),.READBACK("OFF"),.INIT_FILE(""),
 .INIT_00(icon_init_block(bank,0)),
 .INIT_01(icon_init_block(bank,1)),
 .INIT_02(icon_init_block(bank,2)),
 .INIT_03(icon_init_block(bank,3)),
 .INIT_04(icon_init_block(bank,4)),
 .INIT_05(icon_init_block(bank,5)),
 .INIT_06(icon_init_block(bank,6)),
 .INIT_07(icon_init_block(bank,7)),
 .INIT_08(icon_init_block(bank,8)),
 .INIT_09(icon_init_block(bank,9)),
 .INIT_0A(icon_init_block(bank,10)),
 .INIT_0B(icon_init_block(bank,11)),
 .INIT_0C(icon_init_block(bank,12)),
 .INIT_0D(icon_init_block(bank,13)),
 .INIT_0E(icon_init_block(bank,14)),
 .INIT_0F(icon_init_block(bank,15)),
 .INIT_10(icon_init_block(bank,16)),
 .INIT_11(icon_init_block(bank,17)),
 .INIT_12(icon_init_block(bank,18)),
 .INIT_13(icon_init_block(bank,19)),
 .INIT_14(icon_init_block(bank,20)),
 .INIT_15(icon_init_block(bank,21)),
 .INIT_16(icon_init_block(bank,22)),
 .INIT_17(icon_init_block(bank,23)),
 .INIT_18(icon_init_block(bank,24)),
 .INIT_19(icon_init_block(bank,25)),
 .INIT_1A(icon_init_block(bank,26)),
 .INIT_1B(icon_init_block(bank,27)),
 .INIT_1C(icon_init_block(bank,28)),
 .INIT_1D(icon_init_block(bank,29)),
 .INIT_1E(icon_init_block(bank,30)),
 .INIT_1F(icon_init_block(bank,31)),
 .INIT_20(icon_init_block(bank,32)),
 .INIT_21(icon_init_block(bank,33)),
 .INIT_22(icon_init_block(bank,34)),
 .INIT_23(icon_init_block(bank,35)),
 .INIT_24(icon_init_block(bank,36)),
 .INIT_25(icon_init_block(bank,37)),
 .INIT_26(icon_init_block(bank,38)),
 .INIT_27(icon_init_block(bank,39)),
 .INIT_28(icon_init_block(bank,40)),
 .INIT_29(icon_init_block(bank,41)),
 .INIT_2A(icon_init_block(bank,42)),
 .INIT_2B(icon_init_block(bank,43)),
 .INIT_2C(icon_init_block(bank,44)),
 .INIT_2D(icon_init_block(bank,45)),
 .INIT_2E(icon_init_block(bank,46)),
 .INIT_2F(icon_init_block(bank,47)),
 .INIT_30(icon_init_block(bank,48)),
 .INIT_31(icon_init_block(bank,49)),
 .INIT_32(icon_init_block(bank,50)),
 .INIT_33(icon_init_block(bank,51)),
 .INIT_34(icon_init_block(bank,52)),
 .INIT_35(icon_init_block(bank,53)),
 .INIT_36(icon_init_block(bank,54)),
 .INIT_37(icon_init_block(bank,55)),
 .INIT_38(icon_init_block(bank,56)),
 .INIT_39(icon_init_block(bank,57)),
 .INIT_3A(icon_init_block(bank,58)),
 .INIT_3B(icon_init_block(bank,59)),
 .INIT_3C(icon_init_block(bank,60)),
 .INIT_3D(icon_init_block(bank,61)),
 .INIT_3E(icon_init_block(bank,62)),
 .INIT_3F(icon_init_block(bank,63)),
 .INIT_40(icon_init_block(bank,64)),
 .INIT_41(icon_init_block(bank,65)),
 .INIT_42(icon_init_block(bank,66)),
 .INIT_43(icon_init_block(bank,67)),
 .INIT_44(icon_init_block(bank,68)),
 .INIT_45(icon_init_block(bank,69)),
 .INIT_46(icon_init_block(bank,70)),
 .INIT_47(icon_init_block(bank,71)),
 .INIT_48(icon_init_block(bank,72)),
 .INIT_49(icon_init_block(bank,73)),
 .INIT_4A(icon_init_block(bank,74)),
 .INIT_4B(icon_init_block(bank,75)),
 .INIT_4C(icon_init_block(bank,76)),
 .INIT_4D(icon_init_block(bank,77)),
 .INIT_4E(icon_init_block(bank,78)),
 .INIT_4F(icon_init_block(bank,79)),
 .INIT_50(icon_init_block(bank,80)),
 .INIT_51(icon_init_block(bank,81)),
 .INIT_52(icon_init_block(bank,82)),
 .INIT_53(icon_init_block(bank,83)),
 .INIT_54(icon_init_block(bank,84)),
 .INIT_55(icon_init_block(bank,85)),
 .INIT_56(icon_init_block(bank,86)),
 .INIT_57(icon_init_block(bank,87)),
 .INIT_58(icon_init_block(bank,88)),
 .INIT_59(icon_init_block(bank,89)),
 .INIT_5A(icon_init_block(bank,90)),
 .INIT_5B(icon_init_block(bank,91)),
 .INIT_5C(icon_init_block(bank,92)),
 .INIT_5D(icon_init_block(bank,93)),
 .INIT_5E(icon_init_block(bank,94)),
 .INIT_5F(icon_init_block(bank,95)),
 .INIT_60(icon_init_block(bank,96)),
 .INIT_61(icon_init_block(bank,97)),
 .INIT_62(icon_init_block(bank,98)),
 .INIT_63(icon_init_block(bank,99)),
 .INIT_64(icon_init_block(bank,100)),
 .INIT_65(icon_init_block(bank,101)),
 .INIT_66(icon_init_block(bank,102)),
 .INIT_67(icon_init_block(bank,103)),
 .INIT_68(icon_init_block(bank,104)),
 .INIT_69(icon_init_block(bank,105)),
 .INIT_6A(icon_init_block(bank,106)),
 .INIT_6B(icon_init_block(bank,107)),
 .INIT_6C(icon_init_block(bank,108)),
 .INIT_6D(icon_init_block(bank,109)),
 .INIT_6E(icon_init_block(bank,110)),
 .INIT_6F(icon_init_block(bank,111)),
 .INIT_70(icon_init_block(bank,112)),
 .INIT_71(icon_init_block(bank,113)),
 .INIT_72(icon_init_block(bank,114)),
 .INIT_73(icon_init_block(bank,115)),
 .INIT_74(icon_init_block(bank,116)),
 .INIT_75(icon_init_block(bank,117)),
 .INIT_76(icon_init_block(bank,118)),
 .INIT_77(icon_init_block(bank,119)),
 .INIT_78(icon_init_block(bank,120)),
 .INIT_79(icon_init_block(bank,121)),
 .INIT_7A(icon_init_block(bank,122)),
 .INIT_7B(icon_init_block(bank,123)),
 .INIT_7C(icon_init_block(bank,124)),
 .INIT_7D(icon_init_block(bank,125)),
 .INIT_7E(icon_init_block(bank,126)),
 .INIT_7F(icon_init_block(bank,127))
) rom (
 .doa(bank_word[bank]),.dob(),.dia(16'b0),.dib(16'b0),
 .addra(address[10:0]),.addrb(11'b0),
 .bytea(1'b0),.bytewea(1'b0),.byteb(1'b0),.byteweb(1'b0),
 .csa(1'b1),.wea(1'b0),.csb(1'b0),.web(1'b0),
 .clka(clk),.rsta(1'b0),.ocea(1'b1),.clkb(clk),.rstb(1'b0),.oceb(1'b0)
);
end endgenerate
`endif
endmodule
