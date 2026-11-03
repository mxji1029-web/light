
module sd_card_bmp #(
    parameter [31:0] CATALOG_MAGIC=32'h31424c41,
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [6:0]   SCAN_TARGET_COUNT = 7'd64,
    parameter integer AUTO_PLAY_MS      = 6000,     // 自动轮播间隔（毫秒）
    parameter integer DEBOUNCE_MS       = 20        // 按键去抖（毫秒），测试时调小
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO,

    // ---- 口述相册新增：PCM 音频通路 ----
    output                      pcm_fifo_we,      // 写异步 FIFO
    output [31:0]               pcm_fifo_data,    // 两个 16bit 样本打包
    input                       pcm_room_ok,      // FIFO 余量充足
    output                      pcm_found,        // 已找到 APCM 素材

    // ---- 口述相册新增：照片转场握手 ----
    input                       hold,              // 转场进行中：暂停发起新的加载
    input                       paused,            // video-domain playback level; SPI transactions finish safely
    output reg                  disp_commit_toggle, // 新帧提交（转场模块边沿检测用）
    output [5:0]                photo_index,
    output [6:0]                photo_count,
    output                      auto_play_active
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [6:0]       scan_found_total;
wire catalog_reset,catalog_valid;
wire [31:0] catalog_audio_sector;

// ---- 音频通路：SD 仲裁 + PCM 读取 ----
wire             img_sd_req;
wire [31:0]      img_sd_addr;
wire             img_sd_valid;
wire             img_sd_end;
wire             aud_sd_req;
wire [31:0]      aud_sd_addr;
wire             aud_sd_valid;
wire             aud_sd_end;
wire             sd_req_mux;
wire [31:0]      sd_addr_mux;
reg              pcm_started;
wire             pcm_start;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
// Look ahead on increment, with exactly the same reset/hold priority as auto_cnt.
// This keeps the terminal cycle exact and removes its wide equality from load CE.
reg auto_tick_q;
reg [6:0]        img_found_count;
reg [5:0]        img_idx;              // 当前真正显示中的图片编号
reg [5:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sectors[0:63];
// A simple single-write/synchronous-read table avoids a 64:1 mux on the
// same cycle as navigation/timeout arbitration. Metadata guards stale data.
wire table_write = !rst && sd_init_done && !catalog_reset && scan_found_valid && img_found_count<7'd64;
wire [5:0] lookup_index = first_image_committed ? next_from_current : 6'd0;
reg [31:0] lookup_sector;
reg [5:0] lookup_index_d;
reg lookup_valid;
wire index_ready = next_current_tag==img_idx && next_count_tag==img_found_count;
wire lookup_ready = lookup_valid && index_ready && lookup_index_d==lookup_index;
reg              next_req_pending;
reg              load_busy;
// Local guard closes the gap before video busy has crossed back to this domain.
// Both source frames remain protected until busy has been observed high then low.
reg commit_wait,commit_hold_seen;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
reg [5:0] next_from_current;
reg [5:0] next_current_tag;
reg [6:0] next_count_tag;

localparam [31:0] AUTO_PLAY_CYC = (CLK_FREQ_HZ / 1000) * AUTO_PLAY_MS;

// 转场忙标志跨到 sd_card_clk 域（慢速状态，两级同步足够）
reg [1:0] hold_sync;
reg pause_sd_meta /* fehdl keep="true" */;
reg pause_sd_sync;
always @(posedge clk or posedge rst)
 if(rst)begin pause_sd_meta<=0;pause_sd_sync<=0;end
 else begin pause_sd_meta<=(paused===1'b1);pause_sd_sync<=pause_sd_meta;end

// ---- 实板自恢复看门狗 ----
// 1) write_finish 与 source_done 可能同拍错过，用 pending 锁住最后一次“整帧写完”
// 2) 一次加载若因任何原因（BMP 头不符、卡读错、握手错过）永远等不到提交，
//    2.7 s 后强制释放 load_busy，下一次按键可以重试，而不是永久卡死
// 3) 转场 busy 若异常卡住，2.7 s 后忽略它，按键仍然有效
reg              wrfin_pending;
reg [27:0]       load_busy_cnt;
reg [27:0]       hold_cnt;
wire             load_timeout   = (load_busy_cnt == 28'hFFFFFFF);
wire             hold_timeout   = (hold_cnt     == 28'hFFFFFFF);
wire             hold_active    = (hold_sync[1] || commit_wait) && !hold_timeout;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        load_busy_cnt <= 28'd0;
        hold_cnt      <= 28'd0;
    end else begin
        load_busy_cnt <= load_busy ? (load_timeout ? load_busy_cnt : load_busy_cnt + 28'd1) : 28'd0;
        // A deliberately frozen dissolve is not a failed transition.
        if(!pause_sd_sync)
            hold_cnt <= (hold_sync[1] || commit_wait) ? (hold_timeout ? hold_cnt : hold_cnt + 28'd1) : 28'd0;
    end
end

assign write_en   = bmp_data_wr_en;
assign photo_index = img_idx;
assign photo_count = img_found_count;
assign auto_play_active = auto_play_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick  = auto_tick_q;
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [5:0] next_index_limited;
 input [5:0] cur;
 input [6:0] count;
 begin
  if(count<=1 || {1'b0,cur}+7'd1>=count)next_index_limited=0;
  else next_index_limited=cur+6'd1;
 end
endfunction
// Split next-index arithmetic from distributed-RAM addressing. Tags qualify
// the cached result after either the displayed image or catalog count changes.
always @(posedge clk or posedge rst)begin
 if(rst)begin next_from_current<=0;next_current_tag<=0;next_count_tag<=0;end
 else begin
  next_from_current<=next_index_limited(img_idx,img_found_count);
  next_current_tag<=img_idx;next_count_tag<=img_found_count;
 end
end
always @(posedge clk)begin
 if(table_write)img_sectors[img_found_count[5:0]]<=scan_found_sector;
 // Defined write-through also covers a one-entry scan finishing immediately.
 if(table_write && img_found_count[5:0]==lookup_index)lookup_sector<=scan_found_sector;
 else lookup_sector<=img_sectors[lookup_index];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin lookup_index_d<=0;lookup_valid<=0;end
 else begin
  lookup_index_d<=lookup_index;
  lookup_valid<=sd_init_done && !catalog_reset && scan_done && img_found_count!=0 && index_ready;
 end
end

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        commit_wait<=0;commit_hold_seen<=0;
        wrfin_pending         <= 1'b0;
        wrfin_tgl_sync        <= 3'b000;
        hold_sync<=0;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
        img_found_count       <= 7'd0;
        img_idx               <= 6'd0;
        load_idx              <= 6'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;




        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
        disp_commit_toggle    <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        hold_sync        <= {hold_sync[0], hold};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        // 锁住“整帧写完”，避免与 source_done_seen 同拍错过
        if (write_finish_pulse) wrfin_pending <= 1'b1;

        if(commit_wait)begin
            if(hold_sync[1])commit_hold_seen<=1;
            if((commit_hold_seen && !hold_sync[1]) || hold_timeout)commit_wait<=0;
        end

        if (!sd_init_done) begin
            commit_wait<=0;commit_hold_seen<=0;
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
            img_found_count       <= 7'd0;
            img_idx               <= 6'd0;
            load_idx              <= 6'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;




            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // Reset fallback entries before accepting the validated catalog.
            if(catalog_reset) img_found_count<=0;
            else if(scan_found_valid && img_found_count<7'd64)begin
                img_found_count<=img_found_count+7'd1;
            end

            // 加载超时兜底：释放 load_busy，下一次按键可以重试
            if (load_busy && load_timeout) begin
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                wrfin_pending    <= 1'b0;
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_busy && bmp_ready)
                source_done_seen <= 1'b1;

            // 只有真正收到 write_finish_toggle 脉冲，才提交新图并切换显示缓冲区
            if (load_busy && source_done_seen && (write_finish_pulse || wrfin_pending)) begin
                wrfin_pending         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
                commit_wait<=1;commit_hold_seen<=0;
                disp_commit_toggle    <= ~disp_commit_toggle;   // 通知显示端开始转场
            end

            // 上电后自动发起一次“扫描最多 64 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                img_found_count       <= 7'd0;
                img_idx               <= 6'd0;
                load_idx              <= 6'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (key_next_press && scan_done && (img_found_count > 7'd0))
                    next_req_pending <= 1'b1;

                // 自动播放开/关；打开的那一刻立刻切一张，按下去马上有反应
                if (key_auto_press && scan_done && (img_found_count > 7'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                    if (!auto_play_en && !pause_sd_sync)
                        next_req_pending <= 1'b1;
                end

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (!pause_sd_sync)begin
                if (scan_done && auto_play_en && display_valid && !load_busy && !hold_active && first_image_committed && (img_found_count > 7'd1)) begin
                    if (auto_tick)begin
                        auto_cnt <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                    end
                    else
                        begin auto_cnt <= auto_cnt + 32'd1; auto_tick_q <= (auto_cnt == AUTO_PLAY_CYC-32'd2); end
                end else begin
                    auto_cnt <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                end
                end

                // 首图自动加载到 buffer0
                if (scan_done && !first_image_committed && bmp_ready && !load_busy && lookup_ready && (img_found_count != 7'd0)) begin
                    load_idx         <= 6'd0;
                    load_sector      <= lookup_sector;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && !hold_active && lookup_ready && next_req_pending && (img_found_count != 7'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= lookup_sector;
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (!pause_sd_sync && scan_done && bmp_ready && display_valid && !load_busy && !hold_active && lookup_ready && auto_play_en && auto_tick && (img_found_count > 7'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= lookup_sector;
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0; auto_tick_q <= (AUTO_PLAY_CYC == 32'd1);
                end
            end
        end
    end
end

bmp_read #(.CATALOG_MAGIC(CATALOG_MAGIC)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .catalog_reset(catalog_reset),.catalog_valid(catalog_valid),.catalog_audio_sector(catalog_audio_sector),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (img_sd_req),
    .sd_sec_read_addr       (img_sd_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (img_sd_valid),
    .sd_sec_read_end        (img_sd_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

// TB_FAKE_SD swaps the SPI layer for the simulation card model (sim/sd_card_stub.v)
// so the catalog/switch logic can be tested without an SD card.
`ifdef TB_FAKE_SD
sd_card_stub sd_card_top_m0(
`else
sd_card_top sd_card_top_m0(
`endif
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_req_mux),
    .sd_sec_read_addr       (sd_addr_mux),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);
// (the stub takes the same port names, so one instantiation body serves both)

// =====================================================================
// 口述相册：SD 总线仲裁（图像优先） + PCM 音频读卡
// =====================================================================
pcm_sd_arbiter u_sd_arbiter (
    .clk            (clk),
    .rst            (rst),
    .img_req        (img_sd_req),
    .img_addr       (img_sd_addr),
    .img_data_valid (img_sd_valid),
    .img_sec_end    (img_sd_end),
    .aud_req        (aud_sd_req),
    .aud_addr       (aud_sd_addr),
    .aud_data_valid (aud_sd_valid),
    .aud_sec_end    (aud_sd_end),
    .sd_req         (sd_req_mux),
    .sd_addr        (sd_addr_mux),
    .sd_data_valid  (sd_sec_read_data_valid),
    .sd_sec_end     (sd_sec_read_end)
);

// 图片扫描完成后启动音频读取。
// 素材按"图片在前、音频在后"的顺序写入 TF 卡，所以从最后一张图的扇区
// 往后找 APCM 只需扫很短一段，避免从 0 号扇区全盘扫描拖慢开机。
assign pcm_start = scan_done & ~pcm_started;

always @(posedge clk or posedge rst) begin
    if (rst)
        pcm_started <= 1'b0;
    else if (pcm_start)
        pcm_started <= 1'b1;
end

pcm_sd_reader u_pcm_sd_reader (
    .clk        (clk),
    .rst        (rst),
    .start      (pcm_start),
    .scan_start (catalog_valid ? catalog_audio_sector : scan_found_sector),
    .req        (aud_sd_req),
    .addr       (aud_sd_addr),
    .data_valid (aud_sd_valid),
    .sec_end    (aud_sd_end),
    .data       (sd_sec_read_data),
    .fifo_data  (pcm_fifo_data),
    .fifo_we    (pcm_fifo_we),
    .room_ok    (pcm_room_ok),
    .found      (pcm_found),
    .playing    ()
);

endmodule

module key_press_debounce #(
    parameter [31:0] CATALOG_MAGIC=32'h31424c41,
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
