`timescale 1ns/1ps
// Held-payload REQ/ACK mailbox, then a sample-enable-only volume ramp.
// level is synchronous to control_clk; sample_tick is synchronous to audio_clk.
// Both domains share rst. Reset and level10 preserve the original gain255.
module audio_volume_control(
    input control_clk,
    input audio_clk,
    input rst,
    input [3:0] level,
    input sample_tick,
    output reg [7:0] gain
);
function [7:0] level_gain;
    input [3:0] value;
    begin
        case (value)
            4'd0: level_gain = 8'd0;
            4'd1: level_gain = 8'd26;
            4'd2: level_gain = 8'd51;
            4'd3: level_gain = 8'd77;
            4'd4: level_gain = 8'd102;
            4'd5: level_gain = 8'd128;
            4'd6: level_gain = 8'd153;
            4'd7: level_gain = 8'd179;
            4'd8: level_gain = 8'd204;
            4'd9: level_gain = 8'd230;
            default: level_gain = 8'd255; // level10, with 11..15 clamped
        endcase
    end
endfunction

reg [7:0] mailbox_gain;
reg request, acknowledge;
reg [1:0] acknowledge_sync, request_sync;
reg [7:0] data_meta, data_sync, target_gain;
reg [1:0] ramp_count;
wire [7:0] requested_gain = level_gain(level);

always @(posedge control_clk or posedge rst) begin
    if (rst) begin
        mailbox_gain <= 8'd255;
        request <= 1'b0;
        acknowledge_sync <= 2'b00;
    end else begin
        acknowledge_sync <= {acknowledge_sync[0], acknowledge};
        // Keep the payload unchanged until this request's ACK returns.
        // Once idle, capture the current input: busy-time edits merge to latest.
        if (acknowledge_sync[1] == request && requested_gain != mailbox_gain) begin
            mailbox_gain <= requested_gain;
            request <= ~request;
        end
    end
end

always @(posedge audio_clk or posedge rst) begin
    if (rst) begin
        request_sync <= 2'b00;
        data_meta <= 8'd255;
        data_sync <= 8'd255;
        acknowledge <= 1'b0;
        target_gain <= 8'd255;
        gain <= 8'd255;
        ramp_count <= 2'd0;
    end else begin
        request_sync <= {request_sync[0], request};
        data_meta <= mailbox_gain;
        data_sync <= data_meta;
        // Request detection follows two synchronization stages. The bundled
        // payload has also had two stages and remains held until ACK returns.
        if (request_sync[1] != acknowledge) begin
            target_gain <= data_sync;
            acknowledge <= request_sync[1];
        end
        if (sample_tick) begin
            if (gain == target_gain) ramp_count <= 2'd0;
            else if (ramp_count == 2'd3) begin
                ramp_count <= 2'd0;
                if (gain < target_gain) gain <= gain + 8'd1;
                else gain <= gain - 8'd1;
            end else ramp_count <= ramp_count + 2'd1;
        end
    end
end
endmodule
