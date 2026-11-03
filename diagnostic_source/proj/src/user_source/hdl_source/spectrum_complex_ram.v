// 1024 x 32-bit synchronous true dual-port working memory for the FFT.
// The EG4 implementation uses two BRAM32K blocks, preserving the BRAM9K
// resources used by the existing video/audio design. Both read ports have
// one clock of latency. A port writing a word reads that word's old value.
// Cross-port access to the same address when either port writes is outside
// this wrapper's contract and must be avoided by the FFT scheduler.
module spectrum_complex_ram (
    input wire clk,
    input wire [9:0] a_addr,
    input wire [9:0] b_addr,
    input wire a_we,
    input wire b_we,
    input wire [31:0] a_data,
    input wire [31:0] b_data,
    output wire [31:0] a_q,
    output wire [31:0] b_q
);
`ifdef __ICARUS__
    // Icarus cannot read the vendor's protected primitive model. This
    // equivalent branch is selected automatically only by that simulator.
    reg [31:0] words [0:1023];
    reg [31:0] a_read, b_read;
    assign a_q = a_read;
    assign b_q = b_read;
    always @(posedge clk) begin
        a_read <= words[a_addr];
        b_read <= words[b_addr];
        if (a_we) words[a_addr] <= a_data;
        if (b_we) words[b_addr] <= b_data;
    end
`else
    // In 16-bit mode the primitive has 2048 word addresses. The top address
    // bit is tied low, giving 1024 distinct words in each 16-bit lane.
    genvar lane;
    generate for (lane = 0; lane < 2; lane = lane + 1) begin : ram_lane
        EG_PHY_BRAM32K #(
            .MODE("DP16K"),
            .DATA_WIDTH_A("16"), .DATA_WIDTH_B("16"),
            .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL")
        ) words (
            .clka(clk), .clkb(clk),
            .addra({1'b0, a_addr}), .addrb({1'b0, b_addr}),
            .dia(a_data[16*lane +: 16]), .dib(b_data[16*lane +: 16]),
            .doa(a_q[16*lane +: 16]), .dob(b_q[16*lane +: 16]),
            .wea(a_we), .web(b_we), .csa(1'b1), .csb(1'b1),
            .rsta(1'b0), .rstb(1'b0), .ocea(1'b1), .oceb(1'b1),
            .bytea(1'b0), .byteb(1'b0), .bytewea(1'b0), .byteweb(1'b0)
        );
    end endgenerate
`endif
endmodule
