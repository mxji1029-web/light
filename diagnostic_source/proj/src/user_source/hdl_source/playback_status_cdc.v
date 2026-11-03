`timescale 1ns/1ps
// Bundled-data request/ACK mailbox: source_status must be synchronous to source_clk.
// The source holds payload from its ACK until the next frame request. The video
// side waits three clocks for ACK, captures the already settled two-stage bus,
// then commits on a later clock with VS low. A short blank may defer the commit
// to the next blank; it cannot launch another request while a transfer is pending.
module playback_status_cdc(
 input source_clk,input video_clk,input rst,input vs,
 input[7:0] source_status,output reg[7:0] video_status
);
reg request,ack,pending,captured,vs_d;
(* async_reg = "true" *) reg[1:0] request_sync;
(* async_reg = "true" *) reg[2:0] ack_sync;
reg[7:0] payload,payload_meta,payload_sync,capture_data;
always @(posedge source_clk or posedge rst)begin
 if(rst)begin request_sync<=0;ack<=0;payload<=0;end
 else begin
  request_sync<={request_sync[0],request};
  if(request_sync[1]!=ack)begin
   payload<=source_status;
   ack<=request_sync[1];
  end
 end
end
always @(posedge video_clk or posedge rst)begin
 if(rst)begin
  request<=0;pending<=0;captured<=0;vs_d<=1;ack_sync<=0;
  payload_meta<=0;payload_sync<=0;capture_data<=0;video_status<=0;
 end else begin
  vs_d<=vs;
  ack_sync<={ack_sync[1:0],ack};
  payload_meta<=payload;payload_sync<=payload_meta;
  if(vs_d && !vs && !pending)begin
   request<=~request;pending<=1;captured<=0;
  end
  if(pending && !captured && ack_sync[2]==request)begin
   capture_data<=payload_sync;captured<=1;
  end
  if(!vs && pending && captured)begin
   video_status<=capture_data;pending<=0;captured<=0;
  end
 end
end
endmodule
