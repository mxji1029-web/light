
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[3]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]

# ------------------------------------------------------------
# 6. 视频域 <-> 存储/卡域的跨域分组
#
#    依据（report_abnormal_timing_target，routed pr.db 实测）：
#      End Point frame_fifo_read_m0/read_req_d1_reg      video_clk -> ext_mem_clk  slack -1190ps skew 1780ps
#      End Point write_buf/rd_addr_b[6]                  video_clk -> ext_mem_clk  slack -1000ps skew 1780ps
#      End Point sd_card_bmp_m0/hold_sync_reg[1]         video_clk -> sd_card_clk  slack -1044ps skew 1780ps
#    TD 自己对这三条报 PHY-5089“clock skew > 1000ps 跳过”，随后在布线内的
#    hold-fix ECO 里崩溃（place/route 阶段 coredump）。这三条正是
#    frame_fifo_read 的 3 级同步器、rfifo/wfifo 异步 FIFO 读地址、
#    sd_card_bmp 的 2 级同步器，都是 CDC 端点，不做同步 hold 检查。
#
#    注意：这条只切 video/hdmi_5x 与 sd_card/ext_mem 之间的分析，
#    ext_mem_clk 与 sd_card_clk 之间、以及各自域内的时序仍然照常检查。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {video_clk} hdmi_5x_clk] \
    -group [get_clocks {ext_mem_clk} sd_card_clk]

# 50MHz 域里 KEY3 的暂停标志经 2 级同步进 audio_mclk，同样属于 CDC。
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {clk}]

# 实测上面这组 clock group 没有覆盖 video_clk -> sd_card_clk 这一个方向
# （布线后仍报 -887ps、skew 1780ps，端点 u_video_rgb_to_axis_640x480/I_rgb），
# 所以对这一条 CDC 显式切一个方向的检查；反向 sd_card_clk -> video_clk
# （display_valid）仍然照常分析。
set_false_path -from [get_clocks {video_clk}] -to [get_clocks {sd_card_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# Playback pause is a held video-domain level. Only the first audio-domain
# synchronizer stage is asynchronous; meta -> sync remains timed normally.
set_false_path -from [get_clocks {video_clk}] -to [get_regs {pause_audio_meta}]

# Memory controller holds ACK until the SD side withdraws write_req. The SD
# parser now samples this held-level handshake through write_ack_meta/sync.
# Exclude only the first synchronizer stage; meta -> sync remains normally timed.
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_regs {sd_card_bmp_m0/bmp_read_m0/write_ack_meta}]
