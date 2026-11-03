// ---------------------------------------------------------------------------
// pcm_player_i2s.v
// 口述相册项目 · P1 阶段 · V3 版本（数据源 = TF 卡 PCM）
//
// 作用：替代参考例程的 hdmi_audio_tone_i2s_64fs，把"FPGA 内部合成音阶"换成
//       "可替换数据源的 PCM 播放器"。本模块的 I2S 输出时序与旧模块【完全一致】，
//       因此下游的 I2S_receiver / audio_arc_calculate / HDMI 发射核都不用改动。
//
// 版本演进：
//   V1  USE_SINE_TEST=1   内部 64 点正弦表（440Hz），先把播放器与 HDMI 音频通路打通
//   V3  USE_SINE_TEST=0   ← 当前：从异步 FIFO 取 32bit 字，拆成两个 16bit 样本
//                         （FIFO 写侧 = pcm_sd_reader，读 TF 卡上的 APCM 素材）
//
// FIFO 读侧约定（Anlogic IP Generator 生成的 wfifo_32_32_512，SHOW_AHEAD_EN=1）：
//   * 真首字直通（FWFT）：empty_flag=0 时 dout 即为队首字
//   * 与 re 同一拍采样 dout 拿到的就是被弹出的那个字（下一拍 dout 变成新的队首）
//   * 所以本模块里 O_fifo_re 是组合输出，pair <= I_fifo_dout 与 re 同一拍发生
//
// 取样本流程（一个 32bit 字 = 2 个样本，先低 16 位、后高 16 位）：
//   FIFO --pop--> S_pair{hi,lo} --预取--> S_nxt_samp --> 每个 LRCK 帧装进移位寄存器
//   每次只弹一个字、只消费一个样本，所以不会把样本对的奇偶配对打乱。
//   FIFO 空（欠载）时就补静音，不推进任何指针。
//
// 暂停（I_pause）：I2S 时序照常跑，只把样本换成静音、冻结取数指针，
//   所以恢复播放时是"接着刚才那句往下说"，而不是从头开始。
//
// I2S 发送时序（严格对齐旧模块，否则接收端解不出来）：
//   I_mclk      = 12.288 MHz
//   O_i2s_BCLK  : 每拍 I_mclk 翻转一次          -> 6.144 MHz
//   每 64 个 BCLK 为一帧（一个声道），LRCK 在帧尾翻转
//   LRCK 周期   = 128 个 BCLK                   -> 48 kHz
//   数据在 BCLK 由高变低的那一拍移出，MSB 先行
//   接收端取 64bit 移位寄存器的高 24 位 [63:40]
//   —— 所以 16bit 样本必须放在高 16 位（低位补 0）
// ---------------------------------------------------------------------------
module pcm_player_i2s #(
    parameter [31:0] PHASE_INC     = 32'd39370534,  // 440Hz @ 48kHz：440 * 2^32 / 48000
    parameter [7:0]  INIT_VOL      = 8'd255,        // 默认音量（Q8，255 约等于满音量）
    parameter        USE_SINE_TEST = 1'b0           // 1 = 内部正弦（V1 回退），0 = FIFO PCM（V3）
)(
    input               I_mclk,       // 12.288MHz 音频主时钟
    input               I_rst,        // 高有效复位（沿用 rst_all）
    input      [7:0]    I_volume,     // 音量 0~255（0 = 静音）
    input               I_pause,      // 1 = 暂停（静音 + 冻结素材位置）

    // ---- V3 新增：音频异步 FIFO 读侧（与 I_mclk 同域）----
    input      [31:0]   I_fifo_dout,  // 队首：{后一个样本, 前一个样本}
    input               I_fifo_empty, // FIFO 空标志
    output              O_fifo_re,    // 弹出队首（组合输出，与 dout 同拍有效）

    input signed [15:0] I_voice_sample,
    input              I_voice_active,
    output             O_sample_tick,
    output signed [15:0] O_bgm_sample,
    output O_bgm_valid,

    output reg          O_i2s_BCLK,
    output reg          O_i2s_LRCK,
    output reg          O_i2s_DOUT
);

    // ------------------------------------------------------------------
    // I2S 发送时序（与旧模块一致）
    // ------------------------------------------------------------------
    reg  [5:0]  S_bit_cnt;
    reg  [63:0] S_shift_reg;
    reg  [23:0] S_frame_sample24;
    assign O_sample_tick = O_i2s_BCLK && (S_bit_cnt==6'd63) && O_i2s_LRCK;

    // ------------------------------------------------------------------
    // 数据源 A：V1 内部正弦（只作为回退/自检用，V3 默认不走这条路）
    // ------------------------------------------------------------------
    reg  [31:0] S_phase_acc;

    wire [31:0] W_phase_next = S_phase_acc + PHASE_INC;
    wire [5:0]  W_lut_idx    = W_phase_next[31:26];

    function signed [15:0] sine_lut;
        input [5:0] idx;
        begin
            case (idx)
                6'd0 : sine_lut = 16'sd0;      6'd1 : sine_lut = 16'sd1176;
                6'd2 : sine_lut = 16'sd2341;   6'd3 : sine_lut = 16'sd3483;
                6'd4 : sine_lut = 16'sd4592;   6'd5 : sine_lut = 16'sd5657;
                6'd6 : sine_lut = 16'sd6667;   6'd7 : sine_lut = 16'sd7613;
                6'd8 : sine_lut = 16'sd8485;   6'd9 : sine_lut = 16'sd9276;
                6'd10: sine_lut = 16'sd9978;   6'd11: sine_lut = 16'sd10583;
                6'd12: sine_lut = 16'sd11087;  6'd13: sine_lut = 16'sd11483;
                6'd14: sine_lut = 16'sd11769;  6'd15: sine_lut = 16'sd11942;
                6'd16: sine_lut = 16'sd12000;  6'd17: sine_lut = 16'sd11942;
                6'd18: sine_lut = 16'sd11769;  6'd19: sine_lut = 16'sd11483;
                6'd20: sine_lut = 16'sd11087;  6'd21: sine_lut = 16'sd10583;
                6'd22: sine_lut = 16'sd9978;   6'd23: sine_lut = 16'sd9276;
                6'd24: sine_lut = 16'sd8485;   6'd25: sine_lut = 16'sd7613;
                6'd26: sine_lut = 16'sd6667;   6'd27: sine_lut = 16'sd5657;
                6'd28: sine_lut = 16'sd4592;   6'd29: sine_lut = 16'sd3483;
                6'd30: sine_lut = 16'sd2341;   6'd31: sine_lut = 16'sd1176;
                6'd32: sine_lut = 16'sd0;      6'd33: sine_lut = -16'sd1176;
                6'd34: sine_lut = -16'sd2341;  6'd35: sine_lut = -16'sd3483;
                6'd36: sine_lut = -16'sd4592;  6'd37: sine_lut = -16'sd5657;
                6'd38: sine_lut = -16'sd6667;  6'd39: sine_lut = -16'sd7613;
                6'd40: sine_lut = -16'sd8485;  6'd41: sine_lut = -16'sd9276;
                6'd42: sine_lut = -16'sd9978;  6'd43: sine_lut = -16'sd10583;
                6'd44: sine_lut = -16'sd11087; 6'd45: sine_lut = -16'sd11483;
                6'd46: sine_lut = -16'sd11769; 6'd47: sine_lut = -16'sd11942;
                6'd48: sine_lut = -16'sd12000; 6'd49: sine_lut = -16'sd11942;
                6'd50: sine_lut = -16'sd11769; 6'd51: sine_lut = -16'sd11483;
                6'd52: sine_lut = -16'sd11087; 6'd53: sine_lut = -16'sd10583;
                6'd54: sine_lut = -16'sd9978;  6'd55: sine_lut = -16'sd9276;
                6'd56: sine_lut = -16'sd8485;  6'd57: sine_lut = -16'sd7613;
                6'd58: sine_lut = -16'sd6667;  6'd59: sine_lut = -16'sd5657;
                6'd60: sine_lut = -16'sd4592;  6'd61: sine_lut = -16'sd3483;
                6'd62: sine_lut = -16'sd2341;  6'd63: sine_lut = -16'sd1176;
                default: sine_lut = 16'sd0;
            endcase
        end
    endfunction

    wire signed [15:0] W_sine16 = sine_lut(W_lut_idx);

    // ------------------------------------------------------------------
    // 数据源 B：V3 从 FIFO 取 PCM（一个 32bit 字 = 2 个 16bit 样本）
    // ------------------------------------------------------------------
    reg  [31:0] S_pair;         // 从 FIFO 弹出的样本对
    reg         S_pair_valid;   // S_pair 是否还有样本没取完
    reg         S_pair_half;    // 0 = 下一个取低 16 位，1 = 下一个取高 16 位
    reg  [15:0] S_nxt_samp;     // 下一帧要播的样本（1 级前瞻）
    reg         S_nxt_valid;

    // 手上没有样本对、且 FIFO 非空 -> 立刻弹一个字（FWFT：dout 与 re 同拍有效）
    wire W_fifo_pop = (~S_pair_valid) & (~I_fifo_empty) & (~USE_SINE_TEST) & (~I_pause);
    assign O_fifo_re = W_fifo_pop;

    wire [15:0] W_nxt_val  = S_pair_half ? S_pair[31:16] : S_pair[15:0];
    wire        W_nxt_load = (~S_nxt_valid) & S_pair_valid;

    // 下一帧要发送的样本（16bit 有符号）；暂停时直接给静音
    wire signed [15:0] W_background = USE_SINE_TEST ? W_sine16
                                          : (S_nxt_valid ? $signed(S_nxt_samp) : 16'sd0);
    assign O_bgm_sample=W_background;
    assign O_bgm_valid=O_sample_tick && S_nxt_valid && !I_pause && !USE_SINE_TEST;
    wire signed [15:0] W_mixed;
    pcm_mix16 u_mix(.bgm(W_background),.voice(I_voice_active ? I_voice_sample : 16'sd0),
        .bgm_gain(I_voice_active ? 8'd64 : 8'd192),.voice_gain(8'd192),.mixed(W_mixed));
    wire signed [15:0] W_next_sample = I_pause ? 16'sd0 : W_mixed;

    // 音量乘法：Q8 定点，先乘后算术右移 8 位
    wire signed [23:0] W_scaled   = (W_next_sample * $signed({1'b0, I_volume})) >>> 8;

    // 16bit 左对齐成 24bit（低位补 0）；接收端取 [63:40] 正好还原
    wire signed [23:0] W_sample24 = {W_scaled[15:0], 8'd0};

    // ------------------------------------------------------------------
    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            O_i2s_BCLK   <= 1'b0;
            O_i2s_LRCK   <= 1'b0;
            O_i2s_DOUT   <= 1'b0;
            S_bit_cnt    <= 6'd0;
            S_shift_reg  <= 64'd0;
            S_frame_sample24 <= 24'd0;
            S_phase_acc  <= 32'd0;
            S_pair       <= 32'd0;
            S_pair_valid <= 1'b0;
            S_pair_half  <= 1'b0;
            S_nxt_samp   <= 16'd0;
            S_nxt_valid  <= 1'b0;
        end
        else begin
            // ---- FIFO 取数：先弹样本对，再把下一个样本预取到 S_nxt ----
            if (W_fifo_pop) begin
                S_pair       <= I_fifo_dout;
                S_pair_valid <= 1'b1;
                S_pair_half  <= 1'b0;
            end
            else if (W_nxt_load) begin
                S_nxt_samp  <= W_nxt_val;
                S_nxt_valid <= 1'b1;
                if (S_pair_half) begin
                    S_pair_valid <= 1'b0;   // 这个样本对的最后一个样本
                    S_pair_half  <= 1'b0;
                end
                else begin
                    S_pair_half  <= 1'b1;
                end
            end

            // ---- I2S 发送（与旧模块完全一致）----
            O_i2s_BCLK <= ~O_i2s_BCLK;      // 每拍翻转 -> BCLK = 6.144MHz

            if (O_i2s_BCLK == 1'b1) begin
                O_i2s_DOUT  <= S_shift_reg[63];
                S_shift_reg <= {S_shift_reg[62:0], 1'b0};

                if (S_bit_cnt == 6'd63) begin
                    S_bit_cnt <= 6'd0;

                    if (O_i2s_LRCK == 1'b0) begin
                        // 左声道发完：右声道复用同一个样本（单声道转立体声）
                        O_i2s_LRCK  <= 1'b1;
                        S_shift_reg <= {S_frame_sample24, 40'd0};
                    end
                    else begin
                        // 右声道发完：换下一个样本，同时开始下一帧
                        O_i2s_LRCK   <= 1'b0;
                        S_phase_acc  <= W_phase_next;
                        S_shift_reg  <= {W_sample24, 40'd0};
                        S_frame_sample24 <= W_sample24;

                        // FIFO 通路：刚用掉的这个样本出队；只有"真的用上了"才清标志，
                        // 否则会把同一拍刚预取到的新样本误清掉（导致断音）。
                        // 暂停时不消费，指针不动，恢复后接着播。
                        if (!USE_SINE_TEST && S_nxt_valid && !I_pause)
                            S_nxt_valid <= 1'b0;
                    end
                end
                else begin
                    S_bit_cnt <= S_bit_cnt + 6'd1;
                end
            end
        end
    end

endmodule
