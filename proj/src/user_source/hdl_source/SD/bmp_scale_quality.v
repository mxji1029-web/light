// Centered, aspect-preserving BMP canvas. Output order is bottom-up.
// Header setup uses serial arithmetic; no variable combinational divider or
// product lies on the streaming path. The content engine is backpressured while
// this wrapper emits the black bars. At most one output pixel per four clocks
// bounds the rate into the existing non-backpressured frame write FIFO.
module bmp_scale_quality(
 input clk,rst,start,
 input [31:0] base_sector,pixel_offset,
 input [10:0] source_width,source_height,
 input source_top_down,
 input [15:0] target_width,target_height,
 output reg done,
 output sd_sec_read,
 output [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,
 input sd_sec_read_data_valid,sd_sec_read_end,
 output reg pixel_valid,
 output reg [23:0] pixel_data
);
 localparam IDLE=0,MULTIPLY=1,SELECT=2,DIVIDE=3,FIT=4,CENTER=5,LAUNCH=6,RUN=7;
 reg [2:0] state;
 reg [31:0] source_base,source_offset;
 reg [10:0] sw,sh;
 reg top_down;
 reg [15:0] tw,th,fw,fh,left,bottom,right,content_end_y;
 reg [15:0] canvas_x,canvas_y;
 reg [1:0] cooldown;
 reg [26:0] width_product,height_product,width_shift,height_shift;
 reg [15:0] tw_shift,th_shift;
 reg [4:0] setup_count;
 reg fit_width;
 reg [26:0] dividend,quotient;
 reg [11:0] remainder;
 reg [10:0] divisor;
 wire [12:0] next_remainder={remainder,dividend[26]};
 wire quotient_bit=next_remainder>={2'b0,divisor};
 wire [26:0] next_quotient={quotient[25:0],quotient_bit};
 wire inside_content=canvas_x>=left && canvas_x<right &&
                     canvas_y>=bottom && canvas_y<content_end_y;
 reg engine_start;
 wire engine_done,engine_valid;
 wire [23:0] engine_pixel;
 wire engine_ready=state==RUN && inside_content && cooldown==0;
 bmp_bilinear_stream content_engine(
  .clk(clk),.rst(rst),.start(engine_start),
  .base_sector(source_base),.pixel_offset(source_offset),
  .source_width(sw),.source_height(sh),.source_top_down(top_down),
  .target_width(fw),.target_height(fh),.done(engine_done),
  .sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
  .sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid),
  .sd_sec_read_end(sd_sec_read_end),.pixel_ready(engine_ready),
  .pixel_valid(engine_valid),.pixel_data(engine_pixel)
 );
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;source_base<=0;source_offset<=0;sw<=0;sh<=0;top_down<=0;
   tw<=0;th<=0;fw<=0;fh<=0;left<=0;bottom<=0;right<=0;content_end_y<=0;
   canvas_x<=0;canvas_y<=0;cooldown<=0;done<=0;pixel_valid<=0;pixel_data<=0;
   width_product<=0;height_product<=0;width_shift<=0;height_shift<=0;
   tw_shift<=0;th_shift<=0;setup_count<=0;fit_width<=0;
   dividend<=0;quotient<=0;remainder<=0;divisor<=0;engine_start<=0;
  end else begin
   done<=0;pixel_valid<=0;engine_start<=0;
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   case(state)
    IDLE:if(start && source_width!=0 && source_height!=0 && target_width!=0 && target_height!=0)begin
     source_base<=base_sector;source_offset<=pixel_offset;
     sw<=source_width;sh<=source_height;top_down<=source_top_down;
     tw<=target_width;th<=target_height;tw_shift<=target_width;th_shift<=target_height;
     width_shift<={16'b0,source_width};height_shift<={16'b0,source_height};
     width_product<=0;height_product<=0;setup_count<=15;
     canvas_x<=0;canvas_y<=0;cooldown<=0;state<=MULTIPLY;
    end
    MULTIPLY:begin
     if(th_shift[0])width_product<=width_product+width_shift;
     if(tw_shift[0])height_product<=height_product+height_shift;
     width_shift<=width_shift<<1;height_shift<=height_shift<<1;
     tw_shift<=tw_shift>>1;th_shift<=th_shift>>1;
     if(setup_count==0)state<=SELECT;else setup_count<=setup_count-1'b1;
    end
    SELECT:begin
     // Compare SW*TH with SH*TW, then divide the fitted short dimension.
     fit_width<=width_product>height_product;
     if(width_product>height_product)begin
      fw<=tw;dividend<=height_product;divisor<=sw;
     end else begin
      fh<=th;dividend<=width_product;divisor<=sh;
     end
     quotient<=0;remainder<=0;setup_count<=26;state<=DIVIDE;
    end
    DIVIDE:begin
     dividend<={dividend[25:0],1'b0};quotient<=next_quotient;
     if(quotient_bit)remainder<=next_remainder-{2'b0,divisor};
     else remainder<=next_remainder[11:0];
     if(setup_count==0)state<=FIT;else setup_count<=setup_count-1'b1;
    end
    FIT:begin
     if(fit_width)fh<=quotient==0?16'd1:quotient[15:0];
     else fw<=quotient==0?16'd1:quotient[15:0];
     state<=CENTER;
    end
    CENTER:begin
     left<=(tw-fw)>>1;right<=((tw-fw)>>1)+fw;
     // The top edge receives floor(extra/2); scan starts at the bottom.
     bottom<=th-fh-((th-fh)>>1);content_end_y<=th-((th-fh)>>1);
     engine_start<=1;state<=LAUNCH;
    end
    LAUNCH:state<=RUN;
    RUN:if(cooldown==0 && (!inside_content || engine_valid))begin
     pixel_valid<=1;pixel_data<=inside_content?engine_pixel:24'd0;cooldown<=3;
     if(canvas_x+1'b1==tw)begin
      canvas_x<=0;
      if(canvas_y+1'b1==th)begin done<=1;state<=IDLE;end
      else canvas_y<=canvas_y+1'b1;
     end else canvas_x<=canvas_x+1'b1;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
