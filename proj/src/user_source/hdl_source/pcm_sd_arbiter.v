// ---------------------------------------------------------------------------
// pcm_sd_arbiter.v  —  口述相册 P1/V3：SD 总线事务级仲裁
//
// 背景：参考例程的 SPI 读接口约定是「客户端把 sd_sec_read 拉高并保持，
//       直到收到 sd_sec_read_end 才撤销」。所以一张卡上的两个使用者
//       （图像通路 bmp_read、音频通路 pcm_sd_reader）不能简单地用组合 mux
//       切换——必须在一次扇区读事务之间切换，否则会串数据。
//
// 策略：图像优先，事务级切换。
//   - 授权后一直保持到 sd_end 到来，期间不换人
//   - 未被授权的客户端看不到 end / valid，因此会自然等待
//   - 音频让路给图像，切图时音频最多停顿"一个扇区"的时间
// ---------------------------------------------------------------------------
module pcm_sd_arbiter (
    input               clk,
    input               rst,

    // ---- 图像客户端（bmp_read）----
    input               img_req,
    input      [31:0]   img_addr,
    output              img_data_valid,
    output              img_sec_end,

    // ---- 音频客户端（pcm_sd_reader）----
    input               aud_req,
    input      [31:0]   aud_addr,
    output              aud_data_valid,
    output              aud_sec_end,

    // ---- 到 sd_card_top ----
    output              sd_req,
    output     [31:0]   sd_addr,
    input               sd_data_valid,
    input               sd_sec_end
);

    localparam G_NONE = 2'd0;
    localparam G_IMG  = 2'd1;
    localparam G_AUD  = 2'd2;

    // 客户端异常中止（如读图超时直接进入 IDLE）时不会给出 sd_sec_end，
    // 这里用一个"请求已撤销"的看门狗兜底，避免总线被永久占用。
    // 正常事务中客户端会一直保持 req，1 个扇区最长也就几百微秒，
    // 1023 个时钟（约 10us）足够安全。
    localparam [11:0] IDLE_LIMIT = 12'd1023;

    reg [1:0]  grant;
    reg [11:0] idle_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            grant    <= G_NONE;
            idle_cnt <= 12'd0;
        end
        else begin
            case (grant)
            G_NONE: begin
                idle_cnt <= 12'd0;
                // 空闲：图像优先，其次音频
                if (img_req)
                    grant <= G_IMG;
                else if (aud_req)
                    grant <= G_AUD;
            end

            G_IMG: begin
                if (sd_sec_end) begin
                    grant    <= G_NONE;
                    idle_cnt <= 12'd0;
                end
                else if (!img_req) begin
                    if (idle_cnt >= IDLE_LIMIT) begin
                        grant    <= G_NONE;
                        idle_cnt <= 12'd0;
                    end
                    else
                        idle_cnt <= idle_cnt + 12'd1;
                end
                else
                    idle_cnt <= 12'd0;
            end

            G_AUD: begin
                if (sd_sec_end) begin
                    grant    <= G_NONE;
                    idle_cnt <= 12'd0;
                end
                else if (!aud_req) begin
                    if (idle_cnt >= IDLE_LIMIT) begin
                        grant    <= G_NONE;
                        idle_cnt <= 12'd0;
                    end
                    else
                        idle_cnt <= idle_cnt + 12'd1;
                end
                else
                    idle_cnt <= 12'd0;
            end

            default: begin
                grant    <= G_NONE;
                idle_cnt <= 12'd0;
            end
            endcase
        end
    end

    assign sd_req  = (grant == G_IMG) ? img_req :
                     (grant == G_AUD) ? aud_req : 1'b0;
    assign sd_addr = (grant == G_AUD) ? aud_addr : img_addr;

    // 只把数据/结束脉冲发给被授权的那个客户端
    assign img_data_valid = sd_data_valid & (grant == G_IMG);
    assign img_sec_end    = sd_sec_end    & (grant == G_IMG);
    assign aud_data_valid = sd_data_valid & (grant == G_AUD);
    assign aud_sec_end    = sd_sec_end    & (grant == G_AUD);

endmodule
