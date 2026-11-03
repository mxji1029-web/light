// Short spoken-label ROM for staged bring-up; final narration comes from TF.
// Bundled photo id remains stable while its toggle crosses into this domain.
module voice_rom_player #(
    parameter integer SLOT_BITS=13,
    parameter integer LENGTH0=3709,
    parameter integer LENGTH1=3999,
    parameter integer LENGTH2=4209,
    parameter integer LENGTH3=4143,
    parameter ROM_FILE="D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/user_source/hdl_source/rom/voice_test.hex"
)(
    input clk,rst,
    input [5:0] photo_id,
    input photo_toggle,
    input sample_tick,pause,
    output signed [15:0] sample,
    output reg active
);
    localparam ADDRESS_BITS=SLOT_BITS+2;
    reg [7:0] voice_rom[0:(1<<ADDRESS_BITS)-1];
    initial $readmemh(ROM_FILE,voice_rom);
    reg [ADDRESS_BITS-1:0] address;
    reg [7:0] rom_q;
    // Synchronous ROM read permits inference of Anlogic embedded RAM.
    always @(posedge clk) rom_q <= voice_rom[address];
    // One more control stage than data gives the stable bundled id a full
    // destination cycle to settle if it is captured one clock after toggle.
    (* async_reg="true" *) reg [3:0] toggle_sync;
    (* async_reg="true" *) reg [5:0] id_meta,id_sync,id_stable;
    reg toggle_seen;
    reg [1:0] warmup;
    reg [2:0] repeat_count;
    reg [SLOT_BITS:0] remaining;
    wire event_pending=toggle_sync[3]^toggle_seen;
    assign sample=(active && warmup==0 && !event_pending) ? {rom_q,8'd0} : 16'sd0;
    function [SLOT_BITS:0] clip_length;
        input [5:0] selected;
        begin
            case(selected)
                0:clip_length=LENGTH0;1:clip_length=LENGTH1;
                2:clip_length=LENGTH2;3:clip_length=LENGTH3;default:clip_length=0;
            endcase
        end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            toggle_sync<=0;toggle_seen<=0;id_meta<=0;id_sync<=0;id_stable<=0;
            address<=0;warmup<=0;repeat_count<=0;remaining<=0;active<=0;
        end else begin
            toggle_sync<={toggle_sync[2:0],photo_toggle};
            id_meta<=photo_id;id_sync<=id_meta;id_stable<=id_sync;
            if(event_pending)begin
                toggle_seen<=toggle_sync[3];
                address<={id_stable[1:0],{SLOT_BITS{1'b0}}};
                remaining<=clip_length(id_stable);
                active<=(clip_length(id_stable)!=0);
                warmup<=2;repeat_count<=0;
            end else if(warmup!=0) warmup<=warmup-1'b1;
            else if(sample_tick && !pause && active)begin
                if(repeat_count==5)begin
                    repeat_count<=0;
                    if(remaining==1)begin active<=0;remaining<=0;end
                    else begin remaining<=remaining-1'b1;address<=address+1'b1;end
                end else repeat_count<=repeat_count+1'b1;
            end
        end
    end
endmodule
