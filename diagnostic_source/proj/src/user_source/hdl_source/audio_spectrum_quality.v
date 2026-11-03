// Actual PCM -> Hann FFT -> 32 contiguous bands -> frame-coherent gold bars.
// The audio path is observed only: gain/quantization compensation affect pixels.
module audio_spectrum_quality(
 input clk,rst,hs,vs,de,input [23:0] rgb,
 input audio_valid,input signed [15:0] audio_sample,input paused,
 output hs_out,vs_out,de_out,output [23:0] rgb_out
);
 reg [1:0] pause_sync;
 reg initialized,fft_valid;reg signed [15:0] fft_sample;
 reg signed [27:0] dc_acc;
 wire signed [27:0] dc_target=$signed(audio_sample)*28'sd1024;
 wire signed [27:0] dc_error=dc_target-dc_acc;
 wire signed [16:0] ac_sample=$signed(audio_sample)-$signed(dc_acc>>>10);
 wire signed [15:0] scaled_sample=ac_sample>>>2;
 reg [9:0] input_count;reg [39:0] input_energy;
 wire [31:0] sample_square=$signed(scaled_sample)*$signed(scaled_sample);
 wire [39:0] next_energy=input_energy+{8'd0,sample_square};
 reg silent_block;
 wire bin_valid,fft_ready,fft_overrun,display_overrun,display_ready;
 wire [8:0] bin_index;wire [31:0] bin_power;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   pause_sync<=0;initialized<=0;fft_valid<=0;fft_sample<=0;dc_acc<=0;
   input_count<=0;input_energy<=0;silent_block<=1;
  end else begin
   pause_sync<={pause_sync[0],paused};fft_valid<=0;
   if(audio_valid && !pause_sync[1])begin
    fft_valid<=1;
    if(!initialized)begin
     initialized<=1;dc_acc<=dc_target;fft_sample<=0;
     input_energy<=0;input_count<=1;
    end else begin
     dc_acc<=dc_acc+(dc_error>>>10);fft_sample<=scaled_sample;
     if(input_count==1023)begin
      silent_block<=next_energy<40'd65536;input_energy<=0;input_count<=0;
     end else begin input_energy<=next_energy;input_count<=input_count+1'b1;end
    end
   end
  end
 end
 // Valid is already pause-gated upstream; do not discard its one-cycle pipe.
 spectrum_fft1024 fft(.clk(clk),.rst(rst),.sample_valid(fft_valid),
  .sample_data(fft_sample),.paused(1'b0),.block_ready(fft_ready),
  .bin_power(bin_power),.bin_index(bin_index),.bin_valid(bin_valid),.overrun(fft_overrun));
 audio_spectrum_display32 renderer(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
  .paused(pause_sync[1]),.bin_valid(bin_valid),.bin_index(bin_index),.bin_power(bin_power),
  .block_silent(silent_block),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out),
  .block_ready(display_ready),.overrun(display_overrun));
 wire overrun=fft_overrun || display_overrun;
endmodule

module audio_spectrum_display32(
 input clk,rst,hs,vs,de,input [23:0] rgb,input paused,
 input bin_valid,input [8:0] bin_index,input [31:0] bin_power,input block_silent,
 output reg hs_out,vs_out,de_out,output reg [23:0] rgb_out,
 output reg block_ready,overrun
);
 function [9:0] band_start;input [5:0] band;begin
  case(band)
   0:band_start=1;1:band_start=2;2:band_start=3;3:band_start=4;
   4:band_start=5;5:band_start=6;6:band_start=7;7:band_start=8;
   8:band_start=9;9:band_start=11;10:band_start=13;11:band_start=15;
   12:band_start=18;13:band_start=21;14:band_start=25;15:band_start=29;
   16:band_start=35;17:band_start=41;18:band_start=49;19:band_start=57;
   20:band_start=68;21:band_start=80;22:band_start=95;23:band_start=113;
   24:band_start=133;25:band_start=158;26:band_start=187;27:band_start=221;
   28:band_start=261;29:band_start=309;30:band_start=366;31:band_start=433;
   default:band_start=513;
  endcase
 end endfunction
 function [9:0] log2_q4;input [39:0] value;
  reg [39:0] normalized;reg [5:0] exponent;reg [3:0] fraction;
  begin
   normalized=value;exponent=0;
   if(|normalized[39:32])begin normalized=normalized>>32;exponent=32;end
   if(|normalized[31:16])begin normalized=normalized>>16;exponent=exponent+16;end
   if(|normalized[15:8])begin normalized=normalized>>8;exponent=exponent+8;end
   if(|normalized[7:4])begin normalized=normalized>>4;exponent=exponent+4;end
   if(|normalized[3:2])begin normalized=normalized>>2;exponent=exponent+2;end
   if(normalized[1])exponent=exponent+1'b1;
   if(exponent>=4)fraction=(value>>(exponent-4));
   else fraction=(value<<(4-exponent));
   log2_q4=value==0?10'd0:{exponent,fraction};
  end
 endfunction
 function [5:0] mapped_height;input [9:0] value,reference;
  reg signed [11:0] delta;reg [11:0] product13;
  begin
   delta=$signed({2'b0,value})-$signed({2'b0,reference})+12'sd192;
   product13=delta*13+32;
   if(delta<=0)mapped_height=0;
   else if(delta>=192)mapped_height=39;
   else mapped_height=product13>>6;
  end
 endfunction
 localparam IDLE=0,LOG_BANDS=1,SET_REFERENCE=2,MAP_BANDS=3,PUBLISH=4;
 reg [2:0] analysis_state;
 reg [4:0] write_band,map_band;
 // Natural-order FFT bins are contiguous. Keep only the active band's sum;
 // finalizing its logarithm at a boundary avoids a 32x40 register/mux bank.
 reg [39:0] band_energy;
 reg [9:0] work_log[0:31],peak_log,reference_q4,map_reference;
 reg [4:0] reference_fraction;
 wire [5:0] decay_sum={1'b0,reference_fraction}+6'd17;
 reg work_silent;
 reg [5:0] pending_level[0:31],raw_level[0:31];
 reg [5:0] display_level[0:31],display_peak[0:31];
 reg [2:0] peak_hold[0:31];
 // Snapshot the old raw levels at frame_start, then share the display updater.
 reg [5:0] frame_raw_level[0:31];
 reg [4:0] frame_update_index;
 reg frame_update_busy;
 reg vs_d;
 wire frame_start=vs_d && !vs;
 wire [9:0] actual_bin={1'b0,bin_index}+10'd1;
 wire [39:0] completed_energy=bin_index==511?band_energy+{8'd0,bin_power}:band_energy;
 wire [39:0] noise_floor={30'd0,(band_start({1'b0,write_band}+6'd1)-band_start({1'b0,write_band}))}<<1;
 wire [39:0] clean_energy=completed_energy>noise_floor?completed_energy-noise_floor:40'd0;
 wire [9:0] current_log=log2_q4(clean_energy);
 integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   analysis_state<=IDLE;write_band<=0;map_band<=0;peak_log<=0;band_energy<=0;
   reference_q4<=298;map_reference<=298;reference_fraction<=0;work_silent<=1;
   vs_d<=1;block_ready<=0;overrun<=0;
   frame_update_busy<=0;frame_update_index<=0;
   for(i=0;i<32;i=i+1)begin
    work_log[i]<=0;pending_level[i]<=0;raw_level[i]<=0;
    display_level[i]<=0;display_peak[i]<=0;peak_hold[i]<=0;
   end
  end else begin
   vs_d<=vs;block_ready<=0;
   if(frame_start && !paused)begin
    reference_fraction<=decay_sum[4:0];
    if(decay_sum[5] && reference_q4>202)reference_q4<=reference_q4-1'b1;
    // NBAs preserve the original old-raw choice if PUBLISH coincides.
    for(i=0;i<32;i=i+1)frame_raw_level[i]<=raw_level[i];
    frame_update_index<=0;frame_update_busy<=1;
   end else if(frame_update_busy)begin
    // Finish an accepted frame even if pause asserts during these 32 clocks.
    if(frame_raw_level[frame_update_index]>=display_level[frame_update_index])
     display_level[frame_update_index]<=frame_raw_level[frame_update_index];
    else if(display_level[frame_update_index]-frame_raw_level[frame_update_index]>4)
     display_level[frame_update_index]<=display_level[frame_update_index]-4;
    else display_level[frame_update_index]<=frame_raw_level[frame_update_index];
    if(frame_raw_level[frame_update_index]>=display_peak[frame_update_index])begin
     display_peak[frame_update_index]<=frame_raw_level[frame_update_index];
     peak_hold[frame_update_index]<=4;
    end else if(peak_hold[frame_update_index]!=0)
     peak_hold[frame_update_index]<=peak_hold[frame_update_index]-1'b1;
    else if(display_peak[frame_update_index]!=0)
     display_peak[frame_update_index]<=display_peak[frame_update_index]-1'b1;
    if(frame_update_index==31)frame_update_busy<=0;
    else frame_update_index<=frame_update_index+1'b1;
   end
   // FFT output may finish while paused; collect it, but freeze postprocessing.
   if(bin_valid)begin
    if(bin_index==0)begin
     if(analysis_state!=IDLE)overrun<=1;
     write_band<=0;band_energy<={8'd0,bin_power};
    end else if(actual_bin>=band_start({1'b0,write_band}+6'd1))begin
     work_log[write_band]<=current_log;
     write_band<=write_band+1'b1;band_energy<={8'd0,bin_power};
    end else band_energy<=band_energy+{8'd0,bin_power};
    if(bin_index==511)begin
     work_log[write_band]<=current_log;
     analysis_state<=LOG_BANDS;map_band<=0;peak_log<=0;work_silent<=block_silent;
    end
   end
   if(!paused)case(analysis_state)
    LOG_BANDS:begin
     // Preserve the original 32-cycle publish schedule, including pause edges.
     if(work_log[map_band]>peak_log)peak_log<=work_log[map_band];
     if(map_band==31)analysis_state<=SET_REFERENCE;else map_band<=map_band+1'b1;
    end
    SET_REFERENCE:begin
     if(!work_silent && peak_log+10'd16>reference_q4)begin
      reference_q4<=peak_log+10'd16;map_reference<=peak_log+10'd16;
     end else map_reference<=reference_q4;
     map_band<=0;analysis_state<=MAP_BANDS;
    end
    MAP_BANDS:begin
     pending_level[map_band]<=work_silent?6'd0:mapped_height(work_log[map_band],map_reference);
     if(map_band==31)analysis_state<=PUBLISH;else map_band<=map_band+1'b1;
    end
    PUBLISH:begin
     for(i=0;i<32;i=i+1)raw_level[i]<=pending_level[i];
     block_ready<=1;analysis_state<=IDLE;
    end
    default:;
   endcase
  end
 end
 reg [9:0] x_count,y_count;reg de_d;
 wire [9:0] pixel_x=de_d?x_count:10'd0;
 wire [9:0] relative_x=pixel_x-10'd64;
 wire [4:0] column=relative_x[8:4];
 wire [9:0] ordinate=10'd478-y_count;
 wire inside_band=de && pixel_x>=64 && pixel_x<576 && y_count>=440 && y_count<=478;
 wire baseline=inside_band && y_count==478;
 wire in_bar=inside_band && relative_x[3:0]>=3 && relative_x[3:0]<13;
 wire body=in_bar && display_level[column]!=0 && ordinate<display_level[column];
 wire cap=in_bar && display_peak[column]!=0 && ordinate==display_peak[column]-1'b1;
 wire top=body && ordinate+3>=display_level[column];
 wire [23:0] ink=cap || top?24'hf5d393:ordinate>=22?24'he9bd78:ordinate>=10?24'hcda261:24'ha67b47;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x_count<=0;y_count<=0;de_d<=0;hs_out<=1;vs_out<=1;de_out<=0;rgb_out<=0;end
  else begin
   de_d<=de;
   if(!vs)begin x_count<=0;y_count<=0;end
   else if(de)x_count<=pixel_x+10'd1;
   else if(de_d)begin x_count<=0;y_count<=y_count+1'b1;end
   hs_out<=hs;vs_out<=vs;de_out<=de;rgb_out<=body || cap?ink:baseline?24'h806444:rgb;
  end
 end
endmodule
