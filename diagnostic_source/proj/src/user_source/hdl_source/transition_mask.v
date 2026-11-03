// Integer RTL geometry adaptations inspired by gl-transitions.
// gre: directionalwipe, circleopen, wind, windowslice; bobylito: PolkaDotsCurtain.
// MIT attribution/pinned references: third_party/gl_transitions_reference.
// Four clocks, settling inside the reader's >=10-clock burst drain interval.
// Output selects a source spatially; it is not a floating-point alpha value.
module transition_mask(
 input clk,input rst,input[9:0] x,input[9:0] y,
 input[8:0] progress,input[3:0] style,output reg choose_new
);
wire[7:0] gx={2'd0,x[9:4]},gy={1'd0,y[9:3]};
wire[15:0] hx=gx*16'd40503,hy=gy*16'd34283;
wire[15:0] hash_xy=hx^hy;
wire[7:0] h0=hash_xy[7:0]^hash_xy[15:8];
wire[7:0] noise=h0^{3'd0,h0[7:3]};
wire[7:0] row_noise=hy[7:0]^hy[15:8];
wire[9:0] cx={gx[5:0],4'd0}+10'd8,cy={gy[6:0],3'd0}+10'd4;
wire[9:0] dot_x={3'd0,x[6:4],4'd0}+10'd8,dot_y={3'd0,y[6:3],3'd0}+10'd4;
wire[9:0] dx=style==7?(dot_x>=64?dot_x-10'd64:10'd64-dot_x):(cx>=320?cx-10'd320:10'd320-cx);
wire[9:0] dy=style==7?(dot_y>=64?dot_y-10'd64:10'd64-dot_y):(cy>=240?cy-10'd240:10'd240-cy);
wire[13:0] p_wide={5'd0,progress},inverse_p=14'd256-p_wide;
wire[13:0] radius_scale=(p_wide<<4)+(p_wide<<3)+p_wide;
wire[13:0] inverse_scale=(inverse_p<<4)+(inverse_p<<3)+inverse_p;
reg[9:0] radius_base_c;
always @* begin
 radius_base_c=style==9?(inverse_scale>>4):(radius_scale>>4);
 if(style==7)radius_base_c=((p_wide<<1)+p_wide)>>3;

end
reg[7:0] gx1,gy1,noise1,row_noise1;
reg[9:0] dx1,dy1,radius_base1;
reg[8:0] p1,p2,p3;reg[3:0] s1,s2,s3;
reg[19:0] dx2,dy2;
reg[9:0] radius2;
reg[11:0] a2,b2,n2,score3;
reg[20:0] distance3;
reg[19:0] radius_squared3;
reg[11:0] a_c,b_c,n_c;
integer radius_c;
always @* begin
 a_c=0;b_c=0;n_c={5'd0,noise1[6:0]};
 radius_c=radius_base1+noise1[4:0]-16;
 if(s1==7)radius_c=radius_base1+noise1[2:0]-4;
 case(s1)
  0:begin a_c={4'd0,noise1};n_c=0;end
  1:a_c=gx1*12'd24;
  2:begin a_c=gx1*12'd13;b_c=gy1*12'd8;n_c={6'd0,noise1[5:0]};end
  4:a_c={2'd0,gx1[2:0],7'd0};
  5:a_c=(12'd59-gy1)*12'd16;
  6:begin a_c=(dx1>>3)*12'd13;b_c=(dy1>>2)*12'd8;n_c={6'd0,noise1[5:0]};end
  8:begin a_c=gx1*12'd22;n_c={5'd0,row_noise1[6:0]};end
  10:begin a_c=(dx1>>3)*12'd24;b_c=(dy1>>2)*12'd16;end
  11:a_c={2'd0,gy1[2:0],7'd0}; // power-of-two slices: wiring, no modulo/multiply
  default:begin a_c=0;n_c=0;end
 endcase
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  gx1<=0;gy1<=0;noise1<=0;row_noise1<=0;
  dx1<=0;dy1<=0;radius_base1<=0;p1<=0;p2<=0;p3<=0;s1<=0;s2<=0;s3<=0;
  dx2<=0;dy2<=0;radius2<=0;a2<=0;b2<=0;n2<=0;score3<=0;
  distance3<=0;radius_squared3<=0;choose_new<=0;
 end else begin
  // Stage 1: primitive geometry and independently computed noise/radius base.
  gx1<=gx;gy1<=gy;noise1<=noise;row_noise1<=row_noise;
  dx1<=dx;dy1<=dy;radius_base1<=radius_base_c;p1<=progress;s1<=style;
  // Stage 2: isolate multiplication from rank addition and style selection.
  dx2<=dx1*dx1;dy2<=dy1*dy1;
  radius2<=radius_c<0?10'd0:radius_c[9:0];a2<=a_c;b2<=b_c;n2<=n_c;p2<=p1;s2<=s1;
  // Stage 3: no multiply-after-subtract or multiply-plus-rank sum in one cycle.
  distance3<={1'd0,dx2}+{1'd0,dy2};radius_squared3<=radius2*radius2;
  score3<=s2==10?((a2>b2?a2:b2)+n2):(a2+b2+n2);p3<=p2;s3<=s2;
  // Stage 4: output a single registered selector.
  if(p3==0)choose_new<=0;
  else if(p3>=256)choose_new<=1;
  else case(s3)
   0:choose_new<=score3<{3'd0,p3};
   3,7:choose_new<=distance3<{1'd0,radius_squared3};
   9:choose_new<=distance3>={1'd0,radius_squared3};
   default:choose_new<=score3<{1'd0,p3,2'd0};
  endcase
 end
end
endmodule
