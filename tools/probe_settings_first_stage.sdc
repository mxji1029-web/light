# Register collection survives logical -> packed physical pin renaming.
# Only video-clock launches are asynchronous. The clk-to-clk second stage stays timed.
set_false_path -from [get_clocks {video_clk}] -to [get_regs {u_settings_pause_cdc/sync[0]}]
