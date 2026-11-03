// ---------------------------------------------------------------------------
// pcm_sd_reader.v  —  口述相册 P1/V3：从 TF 卡读取 APCM 音频素材
//
// 素材格式（由 PC 端 tools/wav_to_pcm.py 生成）：
//     偏移 0  : "APCM"      4 字节魔数
//     偏移 4  : sample_rate u32 小端（48000）
//     偏移 8  : num_samples u32 小端
//     偏移 12 : channels    u32 小端（1）
//     偏移 16 : 16bit 有符号小端单声道 PCM 数据
//
// 工作流程：
//   ① 从 scan_start 起逐扇区扫描，读每扇区前 4 字节比对 "APCM"
//   ② 命中后重读该扇区：前 16 字节解析头（取 num_samples），其后字节即 PCM
//   ③ 后续扇区顺序读取；两个字节拼成 16bit 样本，两个样本打包成 32bit 写 FIFO
//   ④ 整段播完后回到素材开头循环播放
//
// 流量控制：FIFO 余量不足时不发起新的扇区读（room_ok 由顶层产生）
// ---------------------------------------------------------------------------
module pcm_sd_reader #(
    parameter [31:0] MAX_SCAN_SECTORS = 32'd8192
)(
    input               clk,            // sd_card_clk (100MHz)
    input               rst,
    input               start,          // 图像扫描完成后触发
    input      [31:0]   scan_start,     // 从哪个扇区开始找 APCM

    // ---- 到仲裁器的读请求 ----
    output reg          req,
    output reg [31:0]   addr,
    input               data_valid,
    input               sec_end,
    input      [7:0]    data,

    // ---- 到异步 FIFO（写侧，100MHz 域）----
    output reg [31:0]   fifo_data,      // {样本N+1, 样本N}
    output reg          fifo_we,
    input               room_ok,

    // ---- 状态指示 ----
    output reg          found,
    output reg          playing
);

    localparam S_IDLE      = 3'd0;
    localparam S_SCAN_REQ  = 3'd1;
    localparam S_SCAN_WAIT = 3'd2;
    localparam S_DATA_REQ  = 3'd3;
    localparam S_DATA_WAIT = 3'd4;
    localparam S_NEXT      = 3'd5;

    localparam [31:0] MAGIC_APCM = 32'h4150434D;   // "APCM"

    reg [2:0]  state;
    reg [31:0] hdr_shift;
    reg [4:0]  hdr_bytes;
    reg [31:0] scan_cnt;
    reg [31:0] audio_sector;
    reg [31:0] hdr_cnt;
    reg [31:0] num_samples;
    reg [31:0] last_sample_index;
    reg [31:0] samples_read;
    reg [31:0] cur_sector;
    reg [15:0] samp_lo;
    reg        samp_half;
    reg        pack_half;
    reg [15:0] samp_first;
    reg        samp_is_last;

    wire [31:0] hdr_shift_next = {hdr_shift[23:0], data};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            req          <= 1'b0;
            addr         <= 32'd0;
            fifo_we      <= 1'b0;
            fifo_data    <= 32'd0;
            found        <= 1'b0;
            playing      <= 1'b0;
            hdr_shift    <= 32'd0;
            hdr_bytes    <= 5'd0;
            scan_cnt     <= 32'd0;
            audio_sector <= 32'd0;
            hdr_cnt      <= 32'd0;
            num_samples  <= 32'd0;
            last_sample_index <= 32'd0;
            samples_read <= 32'd0;
            cur_sector   <= 32'd0;
            samp_lo      <= 16'd0;
            samp_half    <= 1'b0;
            pack_half    <= 1'b0;
            samp_first   <= 16'd0;
            samp_is_last <= 1'b0;
        end
        else begin
            fifo_we <= 1'b0;

            case (state)

            // ------------------------------------------------------------
            S_IDLE: begin
                req     <= 1'b0;
                playing <= 1'b0;
                if (start) begin
                    scan_cnt <= 32'd0;
                    found    <= 1'b0;
                    addr     <= scan_start;
                    state    <= S_SCAN_REQ;
                end
            end

            // ------------------------------------------------------------
            S_SCAN_REQ: begin
                req       <= 1'b1;
                hdr_shift <= 32'd0;
                hdr_bytes <= 5'd0;
                state     <= S_SCAN_WAIT;
            end

            S_SCAN_WAIT: begin
                if (data_valid && (hdr_bytes < 5'd4)) begin
                    hdr_shift <= hdr_shift_next;
                    hdr_bytes <= hdr_bytes + 5'd1;
                end

                if (sec_end) begin
                    req <= 1'b0;
                    if ((hdr_bytes == 5'd4) && (hdr_shift == MAGIC_APCM)) begin
                        found        <= 1'b1;
                        audio_sector <= addr;
                        cur_sector   <= addr;
                        addr         <= addr;
                        hdr_cnt      <= 32'd0;
                        num_samples  <= 32'd0;
                        samples_read <= 32'd0;
                        samp_half    <= 1'b0;
                        pack_half    <= 1'b0;
                        state        <= S_DATA_REQ;
                    end
                    else if (scan_cnt >= MAX_SCAN_SECTORS) begin
                        state <= S_IDLE;
                    end
                    else begin
                        scan_cnt <= scan_cnt + 32'd1;
                        addr     <= addr + 32'd1;
                        state    <= S_SCAN_REQ;
                    end
                end
            end

            // ------------------------------------------------------------
            S_DATA_REQ: begin
                if (room_ok) begin
                    req   <= 1'b1;
                    state <= S_DATA_WAIT;
                end
            end

            S_DATA_WAIT: begin
                if (data_valid) begin
                    if (hdr_cnt < 32'd16) begin
                        case (hdr_cnt)
                            32'd8 : num_samples[7:0]   <= data;
                            32'd9 : num_samples[15:8]  <= data;
                            32'd10: num_samples[23:16] <= data;
                            32'd11: num_samples[31:24] <= data;
                            // Count is complete at byte 11. Prepare EOF while
                            // consuming channels, before the first PCM sample.
                            32'd12: last_sample_index <= num_samples - 32'd1;
                            default: ;
                        endcase
                        hdr_cnt <= hdr_cnt + 32'd1;
                    end
                    else if (samples_read < num_samples) begin
                        playing <= 1'b1;
                        if (!samp_half) begin
                            samp_lo   <= {8'd0, data};
                            samp_half <= 1'b1;
                            // Low/high bytes cannot be simultaneous. Register
                            // the comparison now so packing has no add/compare
                            // chain on its high-byte register-enable path.
                            samp_is_last <= (samples_read == last_sample_index);
                        end
                        else begin
                            samp_half <= 1'b0;
                            samples_read <= samples_read + 32'd1;
                            if (!pack_half) begin
                                if (samp_is_last) begin
                                    // Odd sample count: pad only the unused high half.
                                    fifo_data <= {16'd0, data, samp_lo[7:0]};
                                    fifo_we   <= 1'b1;
                                    pack_half <= 1'b0;
                                end else begin
                                    samp_first <= {data, samp_lo[7:0]};
                                    pack_half  <= 1'b1;
                                end
                            end
                            else begin
                                fifo_data <= {{data, samp_lo[7:0]}, samp_first};
                                fifo_we   <= 1'b1;
                                pack_half <= 1'b0;
                            end
                        end
                    end
                end

                if (sec_end) begin
                    req        <= 1'b0;
                    cur_sector <= cur_sector + 32'd1;
                    addr       <= cur_sector + 32'd1;
                    state      <= S_NEXT;
                end
            end

            // ------------------------------------------------------------
            S_NEXT: begin
                if ((num_samples != 32'd0) && (samples_read >= num_samples)) begin
                    samples_read <= 32'd0;
                    // Reread and skip the APCM header on every loop.
                    hdr_cnt    <= 32'd0;
                    samp_half  <= 1'b0;
                    pack_half  <= 1'b0;
                    cur_sector <= audio_sector;
                    addr       <= audio_sector;
                end
                state <= S_DATA_REQ;
            end

            default: state <= S_IDLE;

            endcase
        end
    end

endmodule
