// Picks the caption window for the current lyric position once per frame.
//
// lyric_state_cdc only updates the position during vertical blanking, so the
// caption window is constant for the whole frame and can be resolved by a
// 64-entry table scan (3 clocks per entry) instead of a 45-way combinational
// compare chain. The table itself is generated as a case statement, so it is
// plain logic and cannot be re-packed by the block-RAM inferencer.
//
// Table word: {start[23:0], stop[23:0], base[8:0], count[4:0]}
module lyric_line_lookup #(
 parameter ATOMIC_FRAME=1,
 parameter LINE_FILE="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/lyric_lines.hex"
)(input clk,input rst,input vs,input[23:0] position,
  output reg line_valid,output reg[8:0] line_base,output reg[4:0] line_count);
localparam S_WAIT=2'd0,S_READ=2'd1,S_TEST=2'd2,S_NEXT=2'd3;
reg[1:0] state;reg[6:0] index;reg vs_d;reg[63:0] entry;
reg[23:0] frame_position;
reg candidate_valid;reg[8:0] candidate_base;reg[4:0] candidate_count;
reg[63:0] entry_c;
always @* begin
// BEGIN GENERATED lyric_lines
 entry_c=64'd0;
 case(index)
  7'd0: entry_c=64'h00bb8002a3000003;
  7'd1: entry_c=64'h03a9800546000182;
  7'd2: entry_c=64'h14ed1016eae0028a;
  7'd3: entry_c=64'h16eae01adf300792;
  7'd4: entry_c=64'h1adf301d6d301088;
  7'd5: entry_c=64'h1eedf020f4f0148a;
  7'd6: entry_c=64'h20f4f024efa01992;
  7'd7: entry_c=64'h2506b027d1402287;
  7'd8: entry_c=64'h28f8002c87702609;
  7'd9: entry_c=64'h2cc2202effb02a85;
  7'd10: entry_c=64'h2f17b031ffb02d06;
  7'd11: entry_c=64'h331290368f703009;
  7'd12: entry_c=64'h36a2f03915903487;
  7'd13: entry_c=64'h3920403c6cc03807;
  7'd14: entry_c=64'h3d17c03f18c03b89;
  7'd15: entry_c=64'h3f18c0431f104012;
  7'd16: entry_c=64'h4332f0459fc04908;
  7'd17: entry_c=64'h472350491f704d09;
  7'd18: entry_c=64'h491f704d28605192;
  7'd19: entry_c=64'h4d37004fa9405a89;
  7'd20: entry_c=64'h5130305334c05f09;
  7'd21: entry_c=64'h5334c05735a06392;
  7'd22: entry_c=64'h57441059b4406c88;
  7'd23: entry_c=64'h5b3dd05d37207089;
  7'd24: entry_c=64'h5d3720613dd07512;
  7'd25: entry_c=64'h614fd064b2d07e07;
  7'd26: entry_c=64'h651cc066a8c08184;
  7'd27: entry_c=64'h66a8c06b8f508389;
  7'd28: entry_c=64'h6f240070b8408804;
  7'd29: entry_c=64'h70b8407557008a09;
  7'd30: entry_c=64'h8d684090be208e8f;
  7'd31: entry_c=64'h90be20937a40960c;
  7'd32: entry_c=64'h938f7096e7c09c08;
  7'd33: entry_c=64'h977b209ab660a00f;
  7'd34: entry_c=64'h9ab6609d8930a78c;
  7'd35: entry_c=64'h9d9a10a0cb90ad88;
  7'd36: entry_c=64'ha184a0a394a0b189;
  7'd37: entry_c=64'ha394a0a79190b612;
  7'd38: entry_c=64'ha7a870aa61c0bf08;
  7'd39: entry_c=64'hab8b50ad9250c309;
  7'd40: entry_c=64'had9250b19960c792;
  7'd41: entry_c=64'hb1b160b50950d087;
  7'd42: entry_c=64'hb5c3e0bbe690d40a;
  7'd43: entry_c=64'hbfcf10c5eec0d90a;
  7'd44: entry_c=64'hc5eec0c8fc10de06;
  7'd45: entry_c=64'hddf4c0e41620e10a;
  7'd46: entry_c=64'he41620e7de30e606;
  default: entry_c=64'd0;
 endcase
// END GENERATED lyric_lines
end
wire[23:0] window_start=entry[63:40];
wire[23:0] window_stop=entry[39:16];
wire scan_start=ATOMIC_FRAME ? (!vs_d && vs) : (vs_d && !vs);
wire[23:0] scan_position=ATOMIC_FRAME ? frame_position : position;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=S_WAIT;index<=7'd0;vs_d<=1'b1;entry<=64'd0;
  line_valid<=1'b0;line_base<=9'd0;line_count<=5'd0;
  frame_position<=0;candidate_valid<=0;candidate_base<=0;candidate_count<=0;
 end else begin
  vs_d<=vs;
  case(state)
   S_WAIT:begin
    // The CDC mailbox commits while VS is low. Snapshot only after that phase,
    // then resolve all table entries against the same accepted audio position.
    if(scan_start)begin
     state<=S_READ;index<=7'd0;
     frame_position<=position;
     candidate_valid<=0;candidate_base<=0;candidate_count<=0;
     if(!ATOMIC_FRAME)begin line_valid<=1'b0;line_base<=9'd0;line_count<=5'd0;end
    end
   end
   S_READ:begin entry<=entry_c;state<=S_TEST;end
   S_TEST:begin
    if(window_start<=scan_position && scan_position<window_stop)begin
     if(ATOMIC_FRAME)begin
      candidate_valid<=1'b1;candidate_base<=entry[15:7];candidate_count<=entry[4:0];
     end else begin
      line_valid<=1'b1;line_base<=entry[15:7];line_count<=entry[4:0];
     end
    end
    state<=S_NEXT;
   end
   default:begin
    if(index==7'd63)begin
     state<=S_WAIT;
     if(ATOMIC_FRAME)begin
      line_valid<=candidate_valid;line_base<=candidate_base;line_count<=candidate_count;
     end
    end
    else begin index<=index+7'd1;state<=S_READ;end
   end
  endcase
 end
end
endmodule
