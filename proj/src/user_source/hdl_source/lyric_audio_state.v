// Clock is advanced only when the I2S player consumes a real background sample.
module lyric_audio_state #(parameter [23:0] SAMPLES=24'd15836464)(
 input clk,input rst,input valid,input signed[15:0] sample,
 output reg[23:0] position,output reg[7:0] level
);
reg[7:0] window_count;reg[15:0] peak;
wire[15:0] magnitude=sample[15] ? (~sample+16'd1) : sample;
wire[15:0] maximum=magnitude>peak?magnitude:peak;
wire[7:0] target=maximum[15]?8'd255:maximum[14:7];
always @(posedge clk or posedge rst)begin
 if(rst)begin position<=0;level<=0;window_count<=0;peak<=0;end
 else if(valid)begin
  position<=position==SAMPLES-1?24'd0:position+24'd1;
  window_count<=window_count+1'b1;
  if(window_count==255)begin
   level<=target>=level?target:(level>8?level-8'd8:0);peak<=0;
  end else peak<=maximum;
 end
end
endmodule
