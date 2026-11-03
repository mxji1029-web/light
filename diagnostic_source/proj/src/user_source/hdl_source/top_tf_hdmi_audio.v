// SRAM-only diagnostic image. The card interface is held inactive.
// Six zeroes = all three 8 MiB passes completed without any error.
// Six Fs = data/protocol/timeout error. rst_n starts a fresh complete test.
module top(
    input clk, input rst_n, input key1, input key2, input key3,
    output [5:0] seg_sel, output [7:0] seg_data,
    output HDMI_CLK_P, output HDMI_D2_P, output HDMI_D1_P, output HDMI_D0_P,
    output HDMI_DDC_SCL, inout HDMI_DDC_SDA,
    output sd_ncs, output sd_dclk, output sd_mosi, input sd_miso
);
    wire mem_clk, mem_clk_sft;
    sys_pll sys_pll_m0(.refclk(clk),.reset(!rst_n),.clk0_out(),
        .clk1_out(mem_clk),.clk2_out(mem_clk_sft),.clk3_out());
    reg [15:0] powerup=0;
    always @(posedge mem_clk or negedge rst_n)
        if(!rst_n) powerup<=0;
        else if(!(&powerup)) powerup<=powerup+1'b1;
    wire rst=!( &powerup );
    wire init_done, ref_valid, busy, wr_en, rd_en, rd_valid;
    wire [20:0] wr_addr, rd_addr;
    wire [31:0] wr_data, raw_data;
    wire [3:0] wr_dm;
    reg [31:0] aligned_data;
    always @(posedge mem_clk or posedge rst)
        if(rst) aligned_data<=0;
        else aligned_data<=raw_data;
    sdram U3(.Clk(mem_clk),.Clk_sft(mem_clk_sft),.Rst(rst),
        .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_valid),.Sdr_busy(busy),
        .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_dm(wr_dm),.App_wr_din(wr_data),
        .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(raw_data));
    wire done, passed, failed;
    (* keep = "true" *) wire [31:0] error_count, first_expected, first_actual;
    (* keep = "true" *) wire [20:0] first_error_address;
    wire [3:0] error_flags, phase;
    wire [1:0] pattern_index, first_error_pattern;
    wire [31:0] written_words, checked_words;
    wire [21:0] phase_word;
    sdram_address_selftest #(.WAIT_TIMEOUT_CYCLES(50000000)) test(.mem_clk(mem_clk),.rst(rst),
        .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_valid),.Sdr_busy(busy),
        .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(wr_dm),
        .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(aligned_data),
        .done(done),.pass(passed),.failed(failed),.error_count(error_count),.error_flags(error_flags),
        .first_error_address(first_error_address),.first_expected(first_expected),.first_actual(first_actual),
        .first_error_pattern(first_error_pattern),.pattern_index(pattern_index),.phase(phase),
        .written_words(written_words),.checked_words(checked_words),.phase_word(phase_word));

    // KEY2 (key1/B2) advances the error-detail page; all logic stays in MEM50.
    reg [1:0] key_sync=2'b11;
    reg key_state=1;
    reg [19:0] debounce=0;
    reg [3:0] page=0;
    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin key_sync<=2'b11; key_state<=1; debounce<=0; page<=0; end
        else begin
            key_sync<={key_sync[0],key1};
            if(key_sync[1]==key_state) debounce<=0;
            else if(debounce==20'd799999) begin
                debounce<=0; key_state<=key_sync[1];
                if(!key_sync[1]) page<=(page==8)?0:page+1'b1;
            end else debounce<=debounce+1'b1;
        end
    end
    reg [23:0] value;
    always @* begin
        case(page)
            1: value=error_count[23:0];
            2: value={12'b0,error_flags,error_count[31:24]};
            3: value={3'b0,first_error_address};
            4: value=first_expected[23:0];
            5: value={16'b0,first_expected[31:24]};
            6: value=first_actual[23:0];
            7: value={16'b0,first_actual[31:24]};
            8: value={16'b0,2'b0,first_error_pattern,phase};
            default: value=failed?24'hffffff:(passed?24'h000000:{6{pattern_index+4'd1}});
        endcase
    end
    wire [6:0] digits[0:5];
    genvar i;
    generate for(i=0;i<6;i=i+1) begin: decode
        seg_decoder decoder(.bin_data(value[4*i+:4]),.seg_data(digits[i]));
    end endgenerate
    seg_scan #(.CLK_FREQ(50000000)) scan(.clk(mem_clk),.rst_n(!rst),
        .seg_sel(seg_sel),.seg_data(seg_data),
        .seg_data_0({1'b1,digits[0]}),.seg_data_1({1'b1,digits[1]}),
        .seg_data_2({1'b1,digits[2]}),.seg_data_3({1'b1,digits[3]}),
        .seg_data_4({1'b1,digits[4]}),.seg_data_5({1'b1,digits[5]}));
    assign {HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P}=4'b0000;
    assign HDMI_DDC_SCL=1'b1;
    assign HDMI_DDC_SDA=1'bz;
    assign sd_ncs=1'b1;
    assign sd_dclk=1'b0;
    assign sd_mosi=1'b1;
endmodule
