// Streaming 24-bit BMP bilinear resampler. Align-origin coordinates are
// floor(dst*source/target), with Q8 fractional weights and round-to-nearest
// after each axis. Rows leave bottom-up for the existing frame writer.
// Two synchronous RAMs cache horizontally resampled rows, not source rows.
// A sector is always received in full; only the pixel output has backpressure.
module bmp_bilinear_stream(
 input clk,rst,start,
 input [31:0] base_sector,pixel_offset,
 input [10:0] source_width,source_height,
 input source_top_down,
 input [15:0] target_width,target_height,
 output reg done,
 output reg sd_sec_read,
 output reg [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,
 input sd_sec_read_data_valid,sd_sec_read_end,
 output reg pixel_valid,
 output reg [23:0] pixel_data,
 input pixel_ready
);
 localparam IDLE=0,Y_STEP=1,Y_FRAC=2,RESOLVE0=3,RESOLVE1=4,
  ROW_ADDR=5,X_FRAC=6,FETCH_LEFT=7,FETCH_RIGHT=8,LOOKUP_BYTE=9,
  FILL=10,WAIT_BYTE=11,GET_BYTE=12,H_READY=13,MULTIPLY=14,
  MIX=15,STORE=16,X_STEP=17,READ_LINES=18,WAIT_LINES=19,
  V_READY=20,EMIT=21,TAG_LOOKUP=22;
 reg [4:0] state;
 reg [7:0] sector_ram[0:511];
 reg [23:0] line0[0:639],line1[0:639];
 reg [7:0] cached_byte;
 reg [23:0] line0_q,line1_q;
 reg [8:0] receive_index;
 reg [31:0] base,offset,cache_sector,row_base,byte_address,addr_step;
 reg cache_valid;
 reg [11:0] stride;
 reg [10:0] sw,sh,sy,file_index,load_y,tag0,tag1,xpos;
 reg [10:0] sy1,xpos1,sy_plus_one,xpos_plus_one;
 reg top_down,tag0_valid,tag1_valid,load_bank,y0_bank,y1_bank;
 reg tag0_y0_hit,tag1_y0_hit,tag0_y1_hit,tag1_y1_hit;
 reg [15:0] tw,th,dx,output_row;
 reg signed [17:0] y_rem;
 reg [17:0] x_rem,frac_rem;
 reg [3:0] frac_count;
 reg [7:0] frac_bits,x_fraction,y_fraction;
 reg [10:0] pix0_x,pix1_x,wanted_x;
 reg pix0_valid,pix1_valid,replace_slot,fetch_right;
 reg [23:0] pix0,pix1,left_rgb,right_rgb,fetched_rgb;
 reg [1:0] component;
 reg [23:0] blend_a,blend_b,blend_result;
 reg [7:0] blend_fraction;
 reg vertical_blend;
 reg signed [17:0] product_b,product_g,product_r;
 wire [31:0] wanted_sector=base+(byte_address>>9);
 wire [18:0] frac_doubled={frac_rem,1'b0};
 wire [18:0] frac_den=(state==Y_FRAC)?{3'b000,th}:{3'b000,tw};
 wire frac_one=(frac_doubled>=frac_den);
 wire signed [8:0] delta_b=$signed({1'b0,blend_b[7:0]})-$signed({1'b0,blend_a[7:0]});
 wire signed [8:0] delta_g=$signed({1'b0,blend_b[15:8]})-$signed({1'b0,blend_a[15:8]});
 wire signed [8:0] delta_r=$signed({1'b0,blend_b[23:16]})-$signed({1'b0,blend_a[23:16]});
 wire signed [18:0] sum_b=$signed({3'b000,blend_a[7:0],8'b0})+$signed({product_b[17],product_b})+19'sd128;
 wire signed [18:0] sum_g=$signed({3'b000,blend_a[15:8],8'b0})+$signed({product_g[17],product_g})+19'sd128;
 wire signed [18:0] sum_r=$signed({3'b000,blend_a[23:16],8'b0})+$signed({product_r[17],product_r})+19'sd128;

 // No RAM reset or combinational array reads: all three stores infer RAM.
 always @(posedge clk)begin
  cached_byte<=sector_ram[byte_address[8:0]];
  line0_q<=line0[dx[9:0]];
  line1_q<=line1[dx[9:0]];
  if(state==FILL && sd_sec_read_data_valid)sector_ram[receive_index]<=sd_sec_read_data;
  if(state==STORE)begin
   if(load_bank)line1[dx[9:0]]<=blend_result;
   else line0[dx[9:0]]<=blend_result;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;done<=0;sd_sec_read<=0;sd_sec_read_addr<=0;
   pixel_valid<=0;pixel_data<=0;receive_index<=0;base<=0;offset<=0;
   cache_sector<=0;cache_valid<=0;row_base<=0;byte_address<=0;addr_step<=0;
   stride<=0;sw<=0;sh<=0;sy<=0;file_index<=0;load_y<=0;
   sy1<=0;xpos1<=0;sy_plus_one<=0;xpos_plus_one<=0;
   tag0<=0;tag1<=0;xpos<=0;top_down<=0;tag0_valid<=0;tag1_valid<=0;
   load_bank<=0;y0_bank<=0;y1_bank<=0;tw<=0;th<=0;dx<=0;output_row<=0;
   tag0_y0_hit<=0;tag1_y0_hit<=0;tag0_y1_hit<=0;tag1_y1_hit<=0;
   y_rem<=0;x_rem<=0;frac_rem<=0;frac_count<=0;frac_bits<=0;
   x_fraction<=0;y_fraction<=0;pix0_x<=0;pix1_x<=0;wanted_x<=0;
   pix0_valid<=0;pix1_valid<=0;replace_slot<=0;fetch_right<=0;
   pix0<=0;pix1<=0;left_rgb<=0;right_rgb<=0;fetched_rgb<=0;component<=0;
   blend_a<=0;blend_b<=0;blend_result<=0;blend_fraction<=0;vertical_blend<=0;
   product_b<=0;product_g<=0;product_r<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     pixel_valid<=0;
     if(source_width==0 || source_height==0 || target_width==0 || target_height==0 ||
        source_width>1024 || source_height>1024 || target_width>640 || target_height>480)done<=1;
     else begin
      base<=base_sector;offset<=pixel_offset;sw<=source_width;sh<=source_height;
      tw<=target_width;th<=target_height;top_down<=source_top_down;
      stride<=(({1'b0,source_width}<<1)+source_width+12'd3)&12'hffc;
      sy<=source_height;y_rem<=-$signed({7'b0,source_height});output_row<=0;
      tag0_valid<=0;tag1_valid<=0;cache_valid<=0;dx<=0;state<=Y_STEP;
     end
    end
    Y_STEP:if(y_rem<0)begin
     y_rem<=y_rem+$signed({2'b00,th});sy<=sy-1'b1;
    end else begin
     frac_rem<=y_rem;frac_count<=0;frac_bits<=0;state<=Y_FRAC;
    end
    Y_FRAC:begin
     // The eight fraction cycles provide time to pipeline neighbour selection.
     // Separate +1, boundary clamp, and row-tag lookup into distinct clocks.
     if(frac_count==0)sy_plus_one<=sy+11'd1;
     if(frac_count==1)sy1<=(sy_plus_one<sh)?sy_plus_one:sy;
     frac_rem<=frac_one?frac_doubled-frac_den:frac_doubled;
     frac_bits<={frac_bits[6:0],frac_one};
     if(frac_count==7)begin y_fraction<={frac_bits[6:0],frac_one};state<=TAG_LOOKUP;end
     else frac_count<=frac_count+1'b1;
    end
    TAG_LOOKUP:begin
     // Run after Y_FRAC or a completed STORE. The tags and neighbour indices
     // are then stable, including a tag written by STORE on the preceding edge.
     // Register equality before bank priority and row-address write enables.
     tag0_y0_hit<=tag0_valid && tag0==sy;
     tag1_y0_hit<=tag1_valid && tag1==sy;
     tag0_y1_hit<=tag0_valid && tag0==sy1;
     tag1_y1_hit<=tag1_valid && tag1==sy1;
     state<=RESOLVE0;
    end
    RESOLVE0:begin
     if(tag0_y0_hit)begin y0_bank<=0;state<=RESOLVE1;end
     else if(tag1_y0_hit)begin y0_bank<=1;state<=RESOLVE1;end
     else begin
      // Preserve the neighbouring source row if it is already cached.
      load_bank<=tag0_y1_hit;
      load_y<=sy;file_index<=top_down?sy:sh-1'b1-sy;
      row_base<=offset;addr_step<=stride;state<=ROW_ADDR;
     end
    end
    RESOLVE1:begin
     if(tag0_y1_hit)begin y1_bank<=0;dx<=0;state<=READ_LINES;end
     else if(tag1_y1_hit)begin y1_bank<=1;dx<=0;state<=READ_LINES;end
     else begin
      load_bank<=!y0_bank;load_y<=sy1;
      file_index<=top_down?sy1:sh-1'b1-sy1;
      row_base<=offset;addr_step<=stride;state<=ROW_ADDR;
     end
    end
    ROW_ADDR:if(file_index!=0)begin
     if(file_index[0])row_base<=row_base+addr_step;
     file_index<=file_index>>1;addr_step<=addr_step<<1;
    end else begin
     dx<=0;xpos<=0;x_rem<=0;frac_rem<=0;frac_count<=0;frac_bits<=0;
     pix0_valid<=0;pix1_valid<=0;replace_slot<=0;state<=X_FRAC;
    end
    X_FRAC:begin
     // Keep the increment/clamp out of FETCH_RIGHT's cache-tag/data enables.
     if(frac_count==0)xpos_plus_one<=xpos+11'd1;
     if(frac_count==1)xpos1<=(xpos_plus_one<sw)?xpos_plus_one:xpos;
     frac_rem<=frac_one?frac_doubled-frac_den:frac_doubled;
     frac_bits<={frac_bits[6:0],frac_one};
     if(frac_count==7)begin x_fraction<={frac_bits[6:0],frac_one};state<=FETCH_LEFT;end
     else frac_count<=frac_count+1'b1;
    end
    FETCH_LEFT:begin
     if(pix0_valid && pix0_x==xpos)begin left_rgb<=pix0;state<=FETCH_RIGHT;end
     else if(pix1_valid && pix1_x==xpos)begin left_rgb<=pix1;state<=FETCH_RIGHT;end
     else begin
      wanted_x<=xpos;fetch_right<=0;component<=0;
      byte_address<=row_base+({21'b0,xpos}<<1)+xpos;state<=LOOKUP_BYTE;
     end
    end
    FETCH_RIGHT:begin
     if(pix0_valid && pix0_x==xpos1)begin right_rgb<=pix0;state<=H_READY;end
     else if(pix1_valid && pix1_x==xpos1)begin right_rgb<=pix1;state<=H_READY;end
     else begin
      wanted_x<=xpos1;fetch_right<=1;component<=0;
      byte_address<=row_base+({21'b0,xpos1}<<1)+xpos1;state<=LOOKUP_BYTE;
     end
    end
    LOOKUP_BYTE:if(cache_valid && cache_sector==wanted_sector)state<=WAIT_BYTE;
     else begin
      sd_sec_read_addr<=wanted_sector;sd_sec_read<=1;receive_index<=0;state<=FILL;
     end
    FILL:begin
     if(sd_sec_read_data_valid)receive_index<=receive_index+1'b1;
     if(sd_sec_read_end)begin
      sd_sec_read<=0;cache_sector<=sd_sec_read_addr;cache_valid<=1;state<=LOOKUP_BYTE;
     end
    end
    WAIT_BYTE:state<=GET_BYTE;
    GET_BYTE:begin
     if(component==0)fetched_rgb[7:0]<=cached_byte;
     else if(component==1)fetched_rgb[15:8]<=cached_byte;
     if(component==2)begin
      if(replace_slot)begin pix1<={cached_byte,fetched_rgb[15:0]};pix1_x<=wanted_x;pix1_valid<=1;end
      else begin pix0<={cached_byte,fetched_rgb[15:0]};pix0_x<=wanted_x;pix0_valid<=1;end
      replace_slot<=!replace_slot;
      if(fetch_right)begin right_rgb<={cached_byte,fetched_rgb[15:0]};state<=H_READY;end
      else begin left_rgb<={cached_byte,fetched_rgb[15:0]};state<=FETCH_RIGHT;end
     end else begin component<=component+1'b1;byte_address<=byte_address+1'b1;state<=LOOKUP_BYTE;end
    end
    H_READY:begin
     blend_a<=left_rgb;blend_b<=right_rgb;blend_fraction<=x_fraction;
     vertical_blend<=0;state<=MULTIPLY;
    end
    MULTIPLY:begin
     product_b<=delta_b*$signed({1'b0,blend_fraction});
     product_g<=delta_g*$signed({1'b0,blend_fraction});
     product_r<=delta_r*$signed({1'b0,blend_fraction});
     state<=MIX;
    end
    MIX:begin
     blend_result<={sum_r[15:8],sum_g[15:8],sum_b[15:8]};
     if(vertical_blend)begin
      pixel_data<={sum_r[15:8],sum_g[15:8],sum_b[15:8]};pixel_valid<=1;state<=EMIT;
     end else state<=STORE;
    end
    STORE:begin
     x_rem<=x_rem+sw;
     if(dx+1'b1==tw)begin
     if(load_bank)begin tag1<=load_y;tag1_valid<=1;end
     else begin tag0<=load_y;tag0_valid<=1;end
     state<=TAG_LOOKUP;
    end else begin dx<=dx+1'b1;state<=X_STEP;end
    end
    X_STEP:if(x_rem>=tw)begin x_rem<=x_rem-tw;xpos<=xpos+1'b1;end
     else begin frac_rem<=x_rem;frac_count<=0;frac_bits<=0;state<=X_FRAC;end
    READ_LINES:state<=WAIT_LINES;
    WAIT_LINES:state<=V_READY;
    V_READY:begin
     blend_a<=y0_bank?line1_q:line0_q;blend_b<=y1_bank?line1_q:line0_q;
     blend_fraction<=y_fraction;vertical_blend<=1;state<=MULTIPLY;
    end
    EMIT:if(pixel_ready)begin
     pixel_valid<=0;
     if(dx+1'b1==tw)begin
      if(output_row+1'b1==th)begin done<=1;state<=IDLE;end
      else begin output_row<=output_row+1'b1;y_rem<=y_rem-$signed({7'b0,sh});state<=Y_STEP;end
     end else begin dx<=dx+1'b1;state<=READ_LINES;end
    end
    default:begin state<=IDLE;pixel_valid<=0;sd_sec_read<=0;end
   endcase
  end
 end
endmodule
