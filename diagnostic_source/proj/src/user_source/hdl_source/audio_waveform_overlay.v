// Actual PCM -> 16 Goertzel frequency magnitudes, 1024 samples per block.
// Module interface/name retained for the established video chain.
// One shared signed multiplier; no FFT RAM or invented motion.
module audio_waveform_overlay #(parameter SPECTRUM_QUALITY=1)(
 input clk,input rst,input hs,input vs,input de,input[23:0] rgb,
 input audio_valid,input signed[15:0] audio_sample,input paused,
 output hs_out,output vs_out,output de_out,output[23:0] rgb_out
);
// COEFFICIENTS_BEGIN
function signed[17:0] coefficient;input[3:0] index;begin
 case(index)
  4'd0:coefficient=18'sd131062;
  4'd1:coefficient=18'sd131050;
  4'd2:coefficient=18'sd131033;
  4'd3:coefficient=18'sd130983;
  4'd4:coefficient=18'sd130914;
  4'd5:coefficient=18'sd130717;
  4'd6:coefficient=18'sd130360;
  4'd7:coefficient=18'sd129653;
  4'd8:coefficient=18'sd128230;
  4'd9:coefficient=18'sd125428;
  4'd10:coefficient=18'sd119827;
  4'd11:coefficient=18'sd108982;
  4'd12:coefficient=18'sd88023;
  4'd13:coefficient=18'sd50159;
  4'd14:coefficient=-18'sd12847;
  4'd15:coefficient=-18'sd92682;
 endcase
end endfunction
function signed[17:0] cosine;input[3:0] index;begin
 case(index)
  4'd0:cosine=18'sd65531;
  4'd1:cosine=18'sd65525;
  4'd2:cosine=18'sd65516;
  4'd3:cosine=18'sd65492;
  4'd4:cosine=18'sd65457;
  4'd5:cosine=18'sd65358;
  4'd6:cosine=18'sd65180;
  4'd7:cosine=18'sd64827;
  4'd8:cosine=18'sd64115;
  4'd9:cosine=18'sd62714;
  4'd10:cosine=18'sd59914;
  4'd11:cosine=18'sd54491;
  4'd12:cosine=18'sd44011;
  4'd13:cosine=18'sd25080;
  4'd14:cosine=-18'sd6424;
  4'd15:cosine=-18'sd46341;
 endcase
end endfunction
function signed[17:0] sine;input[3:0] index;begin
 case(index)
  4'd0:sine=18'sd804;
  4'd1:sine=18'sd1206;
  4'd2:sine=18'sd1608;
  4'd3:sine=18'sd2412;
  4'd4:sine=18'sd3216;
  4'd5:sine=18'sd4821;
  4'd6:sine=18'sd6824;
  4'd7:sine=18'sd9616;
  4'd8:sine=18'sd13573;
  4'd9:sine=18'sd19024;
  4'd10:sine=18'sd26558;
  4'd11:sine=18'sd36410;
  4'd12:sine=18'sd48559;
  4'd13:sine=18'sd60547;
  4'd14:sine=18'sd65220;
  4'd15:sine=18'sd46341;
 endcase
end endfunction
// COEFFICIENTS_END
reg signed[28:0] s1[0:15],s2[0:15];
reg[31:0] raw_magnitude[0:15];
reg[5:0] raw_level[0:15],display_level[0:15],display_peak[0:15];
reg[5:0] pending_level[0:15];
reg[3:0] state;
reg[31:0] magnitude_registered;
reg[3:0] bin;
reg[9:0] sample_count;
reg signed[12:0] input_sample;
reg signed[23:0] dc_acc;
reg sample_initialized;
wire signed[11:0] incoming=audio_sample>>>4;
wire signed[23:0] dc_target=$signed(incoming)*24'sd1024;
wire signed[23:0] dc_error=dc_target-dc_acc;
wire signed[12:0] ac_sample=$signed(incoming)-$signed(dc_acc>>>10);
reg signed[28:0] operand_a,last1,last2,real_part;
reg signed[17:0] operand_b;
reg signed[46:0] product;
reg[1:0] pause_sync;
reg overrun,block_ready;
wire signed[46:0] recurrence=(product>>>16)-$signed(s2[bin])+$signed(input_sample);
wire signed[28:0] imag_part=product>>>16;
wire[28:0] abs_real=real_part[28]?-real_part:real_part;
wire[28:0] abs_imag=imag_part[28]?-imag_part:imag_part;
// Phase-insensitive magnitude approximation, <=11.9% error vs Euclidean.
wire[29:0] magnitude_full=abs_real>abs_imag?{1'b0,abs_real}+({1'b0,abs_imag}>>1):
                                                         {1'b0,abs_imag}+({1'b0,abs_real}>>1);
wire[31:0] magnitude=magnitude_full>>4;
// Exact release height mapping as a balanced constant-threshold tree.
// Level 3*(e-4)+q+1 starts at ceil((3+q)*2^e/3), e=4..16, q=0..2.
// The last step is 109227; all larger reachable magnitudes saturate at 39.
// This removes the priority encoder, variable shifts and wide arithmetic.
function[5:0] height;input[31:0] value;begin
 if(|value[31:17])height=6'd39;
 else begin
  if(value[16:0]<17'd1366)begin
   if(value[16:0]<17'd128)begin
    if(value[16:0]<17'd43)begin
     if(value[16:0]<17'd22)begin
      if(value[16:0]<17'd16)begin
       height=6'd0;
      end else begin
       height=6'd1;
      end
     end else begin
      if(value[16:0]<17'd27)begin
       height=6'd2;
      end else begin
       if(value[16:0]<17'd32)begin
        height=6'd3;
       end else begin
        height=6'd4;
       end
      end
     end
    end else begin
     if(value[16:0]<17'd64)begin
      if(value[16:0]<17'd54)begin
       height=6'd5;
      end else begin
       height=6'd6;
      end
     end else begin
      if(value[16:0]<17'd86)begin
       height=6'd7;
      end else begin
       if(value[16:0]<17'd107)begin
        height=6'd8;
       end else begin
        height=6'd9;
       end
      end
     end
    end
   end else begin
    if(value[16:0]<17'd427)begin
     if(value[16:0]<17'd214)begin
      if(value[16:0]<17'd171)begin
       height=6'd10;
      end else begin
       height=6'd11;
      end
     end else begin
      if(value[16:0]<17'd256)begin
       height=6'd12;
      end else begin
       if(value[16:0]<17'd342)begin
        height=6'd13;
       end else begin
        height=6'd14;
       end
      end
     end
    end else begin
     if(value[16:0]<17'd683)begin
      if(value[16:0]<17'd512)begin
       height=6'd15;
      end else begin
       height=6'd16;
      end
     end else begin
      if(value[16:0]<17'd854)begin
       height=6'd17;
      end else begin
       if(value[16:0]<17'd1024)begin
        height=6'd18;
       end else begin
        height=6'd19;
       end
      end
     end
    end
   end
  end else begin
   if(value[16:0]<17'd13654)begin
    if(value[16:0]<17'd4096)begin
     if(value[16:0]<17'd2048)begin
      if(value[16:0]<17'd1707)begin
       height=6'd20;
      end else begin
       height=6'd21;
      end
     end else begin
      if(value[16:0]<17'd2731)begin
       height=6'd22;
      end else begin
       if(value[16:0]<17'd3414)begin
        height=6'd23;
       end else begin
        height=6'd24;
       end
      end
     end
    end else begin
     if(value[16:0]<17'd6827)begin
      if(value[16:0]<17'd5462)begin
       height=6'd25;
      end else begin
       height=6'd26;
      end
     end else begin
      if(value[16:0]<17'd8192)begin
       height=6'd27;
      end else begin
       if(value[16:0]<17'd10923)begin
        height=6'd28;
       end else begin
        height=6'd29;
       end
      end
     end
    end
   end else begin
    if(value[16:0]<17'd43691)begin
     if(value[16:0]<17'd21846)begin
      if(value[16:0]<17'd16384)begin
       height=6'd30;
      end else begin
       height=6'd31;
      end
     end else begin
      if(value[16:0]<17'd27307)begin
       height=6'd32;
      end else begin
       if(value[16:0]<17'd32768)begin
        height=6'd33;
       end else begin
        height=6'd34;
       end
      end
     end
    end else begin
     if(value[16:0]<17'd65536)begin
      if(value[16:0]<17'd54614)begin
       height=6'd35;
      end else begin
       height=6'd36;
      end
     end else begin
      if(value[16:0]<17'd87382)begin
       height=6'd37;
      end else begin
       if(value[16:0]<17'd109227)begin
        height=6'd38;
       end else begin
        height=6'd39;
       end
      end
     end
    end
   end
  end
 end
end endfunction
generate if(!SPECTRUM_QUALITY)begin : legacy
reg legacy_hs,legacy_vs,legacy_de;reg [23:0] legacy_rgb;
integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=0;bin<=0;sample_count<=0;input_sample<=0;operand_a<=0;operand_b<=0;
  product<=0;last1<=0;last2<=0;real_part<=0;pause_sync<=0;overrun<=0;block_ready<=0;
  dc_acc<=0;sample_initialized<=0;magnitude_registered<=0;
  for(i=0;i<16;i=i+1)begin s1[i]<=0;s2[i]<=0;raw_magnitude[i]<=0;raw_level[i]<=0;pending_level[i]<=0;end
 end else begin
  product<=operand_a*operand_b;
  pause_sync<={pause_sync[0],paused};block_ready<=0;
  if(audio_valid && state!=0 && !pause_sync[1])overrun<=1;
  case(state)
   0:if(audio_valid && !pause_sync[1])begin
    if(!sample_initialized)begin dc_acc<=dc_target;input_sample<=0;sample_initialized<=1;end
    else begin dc_acc<=dc_acc+(dc_error>>>10);input_sample<=ac_sample;end
    bin<=0;operand_a<=s1[0];operand_b<=coefficient(0);state<=1;
   end
   1:state<=2;
   2:begin
    if(sample_count==1023)begin
     last1<=recurrence;last2<=s1[bin];s1[bin]<=0;s2[bin]<=0;
     operand_a<=s1[bin];operand_b<=cosine(bin);state<=3;
    end else begin
     s2[bin]<=s1[bin];s1[bin]<=recurrence;
     if(bin==15)begin sample_count<=sample_count+1'b1;state<=0;end
     else begin bin<=bin+1'b1;operand_a<=s1[bin+1'b1];operand_b<=coefficient(bin+1'b1);state<=1;end
    end
   end
   3:state<=4;
   4:begin real_part<=last1-(product>>>16);operand_a<=last2;operand_b<=sine(bin);state<=5;end
   5:state<=6;
   6:begin
    raw_magnitude[bin]<=magnitude;magnitude_registered<=magnitude;state<=7;
   end
   7:begin
    // Separate absolute value/magnitude from logarithmic height for timing.
    pending_level[bin]<=height(magnitude_registered);
    if(bin==15)begin sample_count<=0;state<=8;end
    else begin bin<=bin+1'b1;operand_a<=s1[bin+1'b1];operand_b<=coefficient(bin+1'b1);state<=1;end
   end
   8:begin
    for(i=0;i<16;i=i+1)raw_level[i]<=pending_level[i];
    block_ready<=1;state<=0;
   end
   default:state<=0;
  endcase
 end
end
reg vs_d;reg[1:0] peak_divider;
integer j;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  vs_d<=1;peak_divider<=0;
  for(j=0;j<16;j=j+1)begin display_level[j]<=0;display_peak[j]<=0;end
 end else begin
  vs_d<=vs;
  if(vs_d && !vs && !pause_sync[1])begin
   peak_divider<=peak_divider+1'b1;
   for(j=0;j<16;j=j+1)begin
    if(raw_level[j]>=display_level[j])display_level[j]<=raw_level[j];
    else display_level[j]<=display_level[j]>2?display_level[j]-2:0;
    if(raw_level[j]>=display_peak[j])display_peak[j]<=raw_level[j];
    else if(peak_divider==0 && display_peak[j]!=0)display_peak[j]<=display_peak[j]-1'b1;
   end
  end
 end
end
reg[9:0] x_count,y_count;reg de_d;
wire[9:0] pixel_x=de_d?x_count:10'd0;
wire[9:0] relative_x=pixel_x-10'd64;
wire[3:0] column=relative_x[8:5];
wire[9:0] ordinate=10'd478-y_count;
wire inside_band=de && pixel_x>=64 && pixel_x<576 && y_count>=440 && y_count<=478;
wire baseline=inside_band && y_count==478;
wire in_bar=inside_band && relative_x[4:0]>=4 && relative_x[4:0]<28;
wire body=in_bar && display_level[column]!=0 && ordinate<display_level[column];
wire cap=in_bar && display_peak[column]!=0 && ordinate==display_peak[column]-1'b1;
wire top=body && ordinate+3>=display_level[column];
wire[23:0] ink_rgb=cap || top?24'hf5d393:ordinate>=22?24'he9bd78:ordinate>=10?24'hcda261:24'ha67b47;
always @(posedge clk or posedge rst)begin
 if(rst)begin x_count<=0;y_count<=0;de_d<=0;legacy_hs<=1;legacy_vs<=1;legacy_de<=0;legacy_rgb<=0;end
 else begin
  de_d<=de;
  if(!vs)begin x_count<=0;y_count<=0;end
  else if(de)x_count<=pixel_x+10'd1;
  else if(de_d)begin x_count<=0;y_count<=y_count+1'b1;end
  legacy_hs<=hs;legacy_vs<=vs;legacy_de<=de;
  legacy_rgb<=body || cap?ink_rgb:baseline?24'h806444:rgb;
 end
end
assign hs_out=legacy_hs;assign vs_out=legacy_vs;assign de_out=legacy_de;assign rgb_out=legacy_rgb;
end else begin : quality
audio_spectrum_quality engine(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
.audio_valid(audio_valid),.audio_sample(audio_sample),.paused(paused),
.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb_out(rgb_out));
end endgenerate
endmodule
