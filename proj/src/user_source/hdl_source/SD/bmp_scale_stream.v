// Nearest-neighbour BMP resampler, one 512-byte synchronous sector cache.
// No division, multiplication, source line RAM or SD byte backpressure.
// Output is always bottom-up to match frame_fifo_write's vertical mapping.
module bmp_scale_stream(
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
 output reg [23:0] pixel_data
);
 localparam IDLE=0,PREP=1,VSTEP=2,PIXADDR=3,FILL=4,WAIT_RAM=5,
            BYTE=6,EMIT=7,HSTEP=8,ROW=9;
 reg [3:0] state;
 reg [7:0] sector_ram[0:511];
 reg [8:0] receive_index;
 reg [7:0] cached_byte;
 reg [31:0] cache_sector;
 reg cache_valid;
 reg [31:0] base,row_offset,byte_offset;
 reg [11:0] stride;
 reg [10:0] sw,sh,prep_left;
 reg top_down;
 reg [15:0] tw,th,dx,dy;
 reg [16:0] x_acc,y_acc;
 reg [11:0] x_byte;
 reg x_advanced;
 reg [1:0] component;
 reg [23:0] rgb;
 wire [31:0] wanted_sector=base+(byte_offset>>9);
 // The read port is synchronous; WAIT_RAM provides its one-cycle latency.
 always @(posedge clk) begin
  cached_byte<=sector_ram[byte_offset[8:0]];
  if(state==FILL && sd_sec_read_data_valid)
   sector_ram[receive_index]<=sd_sec_read_data;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;done<=0;sd_sec_read<=0;sd_sec_read_addr<=0;
   pixel_valid<=0;pixel_data<=0;receive_index<=0;cache_sector<=0;cache_valid<=0;
   base<=0;row_offset<=0;byte_offset<=0;stride<=0;sw<=0;sh<=0;prep_left<=0;
   top_down<=0;tw<=0;th<=0;dx<=0;dy<=0;x_acc<=0;y_acc<=0;x_byte<=0;x_advanced<=0;component<=0;rgb<=0;
  end else begin
   done<=0;pixel_valid<=0;
   case(state)
    IDLE:if(start)begin
     base<=base_sector;row_offset<=pixel_offset;
     stride<=(({1'b0,source_width}<<1)+source_width+12'd3)&12'hffc;
     sw<=source_width;sh<=source_height;tw<=target_width;th<=target_height;
     top_down<=source_top_down;prep_left<=source_top_down?source_height-1'b1:11'd0;
     dx<=0;dy<=0;x_acc<=0;x_byte<=0;component<=0;cache_valid<=0;
     // ceil((destination_bottom_row+1)*sh/th)-1 for reversed output rows.
     y_acc<=source_height-1'b1;
     state<=PREP;
    end
    PREP:if(prep_left!=0)begin
     row_offset<=row_offset+stride;prep_left<=prep_left-1'b1;
    end else state<=VSTEP;
    VSTEP:if(y_acc>=th)begin
     y_acc<=y_acc-th;
     row_offset<=top_down?row_offset-stride:row_offset+stride;
    end else begin
     byte_offset<=row_offset;component<=0;state<=PIXADDR;
    end
    PIXADDR:if(cache_valid && cache_sector==wanted_sector)state<=WAIT_RAM;
     else begin
      sd_sec_read_addr<=wanted_sector;sd_sec_read<=1;receive_index<=0;state<=FILL;
     end
    FILL:begin
     if(sd_sec_read_data_valid)receive_index<=receive_index+1'b1;
     if(sd_sec_read_end)begin
      sd_sec_read<=0;cache_sector<=sd_sec_read_addr;cache_valid<=1;state<=PIXADDR;
     end
    end
    WAIT_RAM:state<=BYTE;
    BYTE:begin
     case(component)
      0:rgb[7:0]<=cached_byte;
      1:rgb[15:8]<=cached_byte;
      2:rgb[23:16]<=cached_byte;
      default:;
     endcase
     if(component==2)state<=EMIT;
     else begin component<=component+1'b1;byte_offset<=byte_offset+1'b1;state<=PIXADDR;end
    end
    EMIT:begin
     pixel_valid<=1;pixel_data<=rgb;
     x_advanced<=0;
     if(dx+1'b1==tw)begin
      dx<=0;x_acc<=0;x_byte<=0;
      if(dy+1'b1==th)begin done<=1;state<=IDLE;end
      else begin dy<=dy+1'b1;y_acc<=y_acc+sh;state<=ROW;end
     end else begin dx<=dx+1'b1;x_acc<=x_acc+sw;state<=HSTEP;end
    end
    HSTEP:if(x_acc>=tw)begin
     x_acc<=x_acc-tw;x_byte<=x_byte+12'd3;x_advanced<=1;
    end else if(!x_advanced)begin
     // Horizontal upsampling repeats the decoded RGB, including a pixel that
     // straddles two sectors; never reload both sectors for every duplicate.
     state<=EMIT;
    end else begin byte_offset<=row_offset+x_byte;component<=0;state<=PIXADDR;end
    ROW:state<=VSTEP;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
