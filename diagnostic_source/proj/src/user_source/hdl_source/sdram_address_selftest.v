`timescale 1ns/1ps
// Destructive SDRAM-only diagnostic. It owns the App interface exclusively.
// Defaults cover all 2M x 32-bit words (8 MiB); no TF/card interface is used.
// App_* is the existing vendor streaming interface, NOT a ready/valid bus:
// admit a block only while !busy && !init_ref_vld; then issue every word
// contiguously even when the controller raises its own busy indication.
module sdram_address_selftest #(
    parameter integer ADDR_BITS = 21,
    parameter integer TEST_WORDS = 2097152,
    parameter integer BLOCK_WORDS = 256,
    parameter integer DRAIN_CYCLES = 32,
    parameter integer WAIT_TIMEOUT_CYCLES = 40000000
)(
    input wire mem_clk,
    input wire rst,
    input wire Sdr_init_done,
    input wire Sdr_init_ref_vld,
    input wire Sdr_busy,
    output wire App_wr_en,
    output wire [ADDR_BITS-1:0] App_wr_addr,
    output wire [31:0] App_wr_din,
    output wire [3:0] App_wr_dm,
    output wire App_rd_en,
    output wire [ADDR_BITS-1:0] App_rd_addr,
    input wire Sdr_rd_en,
    input wire [31:0] Sdr_rd_dout,
    output reg done,
    output wire pass,
    output wire failed,
    output reg [31:0] error_count,
    // bit0=data mismatch, bit1=protocol/illegal-phase error, bit2=timeout,
    // bit3=init_done dropped after the test had started.
    output reg [3:0] error_flags,
    output reg [ADDR_BITS-1:0] first_error_address,
    output reg [31:0] first_expected,
    output reg [31:0] first_actual,
    output reg [1:0] first_error_pattern,
    output reg [1:0] pattern_index,
    output reg [3:0] phase,
    output reg [31:0] written_words,
    output reg [31:0] checked_words,
    output wire [ADDR_BITS:0] phase_word
);
    localparam WAIT_INIT=0, WRITE_WAIT=1, WRITE_RUN=2, WRITE_DRAIN=3,
               READ_WAIT=4, READ_RUN=5, READ_DRAIN=6, COMPLETE=7;
    reg [ADDR_BITS:0] write_count, read_issue_count, read_check_count;
    reg [15:0] block_count;
    reg [15:0] drain_count;
    reg [31:0] wait_count;
    wire read_phase=(phase==READ_RUN || phase==READ_DRAIN);
    wire eligible=(!Sdr_busy && !Sdr_init_ref_vld);
    wire response_expected=read_phase && read_check_count<read_issue_count;
    wire progress=App_wr_en || App_rd_en || (Sdr_rd_en && response_expected);
    wire [31:0] expected_word=pattern_word(pattern_index,read_check_count[ADDR_BITS-1:0]);
    assign App_wr_en=(phase==WRITE_RUN) && (block_count!=0 || eligible);
    assign App_rd_en=(phase==READ_RUN) && (block_count!=0 || eligible);
    assign App_wr_addr=write_count[ADDR_BITS-1:0];
    assign App_rd_addr=read_issue_count[ADDR_BITS-1:0];
    assign App_wr_din=pattern_word(pattern_index,write_count[ADDR_BITS-1:0]);
    assign App_wr_dm=4'b0000;
    assign failed=(error_count!=0) || (error_flags!=0);
    assign pass=done && !failed;
    assign phase_word=read_phase || phase==READ_WAIT ? read_check_count : write_count;

    // Mode 0 tests address aliases. Mode 1 stresses alternating bit values.
    // Mode 2 is a reversible xorshift hash of address+seed; expectation is
    // independently reproducible without storing a full expected-data RAM.
    function [31:0] pattern_word;
        input [1:0] mode;
        input [ADDR_BITS-1:0] address;
        reg [31:0] v;
        begin
            v=address;
            case(mode)
                0: pattern_word=v ^ 32'ha5c39e71;
                1: pattern_word=address[0] ? 32'haa55aa55 : 32'h55aa55aa;
                default: begin
                    v=v ^ 32'h6d2b79f5;
                    v=v ^ (v<<13);
                    v=v ^ (v>>17);
                    v=v ^ (v<<5);
                    pattern_word=v;
                end
            endcase
        end
    endfunction

    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin
            phase<=WAIT_INIT; pattern_index<=0; done<=0;
            error_count<=0; error_flags<=0; first_error_address<=0;
            first_expected<=0; first_actual<=0; first_error_pattern<=0;
            write_count<=0; read_issue_count<=0; read_check_count<=0;
            block_count<=0; drain_count<=0; wait_count<=0;
            written_words<=0; checked_words<=0;
        end else if(!done) begin
            if(progress) wait_count<=0;
            else if(wait_count<WAIT_TIMEOUT_CYCLES) wait_count<=wait_count+1'b1;

            // Count/check every response, including block tails. A response
            // without an outstanding address is a protocol error, not padding.
            if(Sdr_rd_en) begin
                if(response_expected) begin
                    read_check_count<=read_check_count+1'b1;
                    checked_words<=checked_words+1'b1;
                    // Case inequality also rejects X/Z from a faulty or
                    // undriven simulation backend; physical binary hardware
                    // implements the same 32-bit inequality comparison.
                    if(Sdr_rd_dout!==expected_word) begin
                        error_flags[0]<=1'b1;
                        if(error_count!=32'hffffffff) error_count<=error_count+1'b1;
                        if(error_count==0 && error_flags==0) begin
                            first_error_address<=read_check_count[ADDR_BITS-1:0];
                            first_expected<=expected_word;
                            first_actual<=Sdr_rd_dout;
                            first_error_pattern<=pattern_index;
                        end
                    end
                end else begin
                    error_flags[1]<=1'b1;
                    if(error_count!=32'hffffffff) error_count<=error_count+1'b1;
                    if(error_count==0 && error_flags==0) begin
                        first_error_address<=read_check_count[ADDR_BITS-1:0];
                        first_expected<=0; first_actual<=Sdr_rd_dout;
                        first_error_pattern<=pattern_index;
                    end
                end
            end

            case(phase)
                WAIT_INIT: if(Sdr_init_done) begin
                    phase<=WRITE_WAIT; wait_count<=0;
                end
                WRITE_WAIT: begin
                    block_count<=0; drain_count<=0;
                    if(eligible) phase<=WRITE_RUN;
                end
                WRITE_RUN: if(App_wr_en) begin
                    write_count<=write_count+1'b1;
                    written_words<=written_words+1'b1;
                    if(block_count==BLOCK_WORDS-1 || write_count==TEST_WORDS-1) begin
                        phase<=WRITE_DRAIN; drain_count<=0;
                    end else block_count<=block_count+1'b1;
                end
                WRITE_DRAIN: begin
                    if(drain_count<DRAIN_CYCLES) drain_count<=drain_count+1'b1;
                    if(drain_count>=DRAIN_CYCLES && eligible) begin
                        if(write_count==TEST_WORDS) begin
                            read_issue_count<=0; read_check_count<=0;
                            phase<=READ_WAIT;
                        end else phase<=WRITE_WAIT;
                    end
                end
                READ_WAIT: begin
                    block_count<=0; drain_count<=0;
                    if(eligible) phase<=READ_RUN;
                end
                READ_RUN: if(App_rd_en) begin
                    read_issue_count<=read_issue_count+1'b1;
                    if(block_count==BLOCK_WORDS-1 || read_issue_count==TEST_WORDS-1) begin
                        phase<=READ_DRAIN; drain_count<=0;
                    end else block_count<=block_count+1'b1;
                end
                READ_DRAIN: begin
                    if(drain_count<DRAIN_CYCLES) drain_count<=drain_count+1'b1;
                    if(drain_count>=DRAIN_CYCLES && eligible && read_check_count==read_issue_count) begin
                        if(read_issue_count==TEST_WORDS) begin
                            if(pattern_index==2) begin phase<=COMPLETE; done<=1; end
                            else begin
                                pattern_index<=pattern_index+1'b1;
                                write_count<=0; phase<=WRITE_WAIT;
                            end
                        end else phase<=READ_WAIT;
                    end
                end
                default: begin
                    error_flags[1]<=1'b1;
                    phase<=COMPLETE; done<=1;
                end
            endcase

            if(wait_count>=WAIT_TIMEOUT_CYCLES) begin
                error_flags[2]<=1'b1; done<=1; phase<=COMPLETE;
                if(error_count==0 && error_flags==0) begin
                    first_error_address<=read_check_count[ADDR_BITS-1:0];
                    first_expected<=expected_word; first_actual<=Sdr_rd_dout;
                    first_error_pattern<=pattern_index;
                end
            end
            if(phase!=WAIT_INIT && !Sdr_init_done) begin
                error_flags[3]<=1'b1; done<=1; phase<=COMPLETE;
            end
        end
    end
endmodule
