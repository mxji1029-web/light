// Frame-coherent brightness/contrast for the photo only, before text/waveform.
// Contrast Q6 gains: 32/48/64/80/96 -> 50/75/100/125/150 percent.
module photo_adjust(
 input clk,input rst,input hs,input vs,input de,input[23:0] rgb,
 input signed[7:0] brightness,input[2:0] contrast_level,input settings_active,input selected,
 output reg hs_out,output reg vs_out,output reg de_out,output reg[23:0] rgb_out,
 output reg signed[7:0] frame_brightness,output reg[2:0] frame_contrast,
 output reg frame_active,output reg frame_selected
);
reg vs_d;
always @(posedge clk or posedge rst)begin
 if(rst)begin vs_d<=1;frame_brightness<=0;frame_contrast<=2;frame_active<=0;frame_selected<=0;end
 else begin
  vs_d<=vs;
  if(vs_d && !vs)begin
   frame_brightness<=brightness;frame_contrast<=contrast_level;
   frame_active<=settings_active;frame_selected<=selected;
  end
 end
end
wire[7:0] gain=8'd32+{1'b0,frame_contrast,4'd0};
wire signed[8:0] centered_r=$signed({1'b0,rgb[23:16]})-9'sd128;
wire signed[8:0] centered_g=$signed({1'b0,rgb[15:8]})-9'sd128;
wire signed[8:0] centered_b=$signed({1'b0,rgb[7:0]})-9'sd128;
reg signed[17:0] product_r,product_g,product_b;
reg signed[7:0] brightness0;
reg[2:0] sync0;
wire signed[18:0] correction={{11{brightness0[7]}},brightness0};
// Arithmetic quotient is floor(value/64); low bits are its nonnegative residue.
// Round nearest, ties to even, including negative halfway values.
function signed[18:0] round_q6;
 input signed[17:0] value;
 reg signed[18:0] quotient;
 begin
  quotient=$signed(value)>>>6;
  if(value[5] && ((|value[4:0]) || value[6]))quotient=quotient+19'sd1;
  round_q6=quotient;
 end
endfunction
wire signed[18:0] result_r=round_q6(product_r)+19'sd128+correction;
wire signed[18:0] result_g=round_q6(product_g)+19'sd128+correction;
wire signed[18:0] result_b=round_q6(product_b)+19'sd128+correction;
function[7:0] clip;input signed[18:0] value;begin
 if(value<0)clip=0;else if(value>255)clip=255;else clip=value[7:0];
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  product_r<=0;product_g<=0;product_b<=0;brightness0<=0;sync0<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  product_r<=centered_r*$signed({1'b0,gain});
  product_g<=centered_g*$signed({1'b0,gain});
  product_b<=centered_b*$signed({1'b0,gain});
  brightness0<=frame_brightness;sync0<={hs,vs,de};
  {hs_out,vs_out,de_out}<=sync0;
  rgb_out<={clip(result_r),clip(result_g),clip(result_b)};
 end
end
endmodule
