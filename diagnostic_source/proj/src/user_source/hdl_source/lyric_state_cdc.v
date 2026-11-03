// Bundled-data mailbox. Source payload is held from acknowledge until next request.
// Video accepts only during vertical sync, keeping all active pixels frame-coherent.
module lyric_state_cdc(
 input audio_clk,input video_clk,input rst,input vs,
 input[23:0] audio_position,input[7:0] audio_level,
 output reg[23:0] position,output reg[7:0] level
);
reg request,ack,pending,vs_d;
reg[1:0] request_sync;reg[3:0] ack_sync;
reg[31:0] payload,data_meta,data_sync;
always @(posedge audio_clk or posedge rst)begin
 if(rst)begin request_sync<=0;ack<=0;payload<=0;end
 else begin
  request_sync<={request_sync[0],request};
  if(request_sync[1]!=ack)begin payload<={audio_level,audio_position};ack<=request_sync[1];end
 end
end
always @(posedge video_clk or posedge rst)begin
 if(rst)begin request<=0;pending<=0;vs_d<=1;ack_sync<=0;data_meta<=0;data_sync<=0;position<=0;level<=0;end
 else begin
  vs_d<=vs;ack_sync<={ack_sync[2:0],ack};data_meta<=payload;data_sync<=data_meta;
  if(vs_d && !vs && !pending)begin request<=~request;pending<=1;end
  if(!vs && pending && ack_sync[3]==request)begin
   {level,position}<=data_sync;pending<=0;
  end
 end
end
endmodule
