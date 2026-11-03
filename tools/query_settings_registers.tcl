import_db D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0_gate.db
puts "REGS_SYNC_ONLY: [get_regs {u_settings_pause_cdc/sync*}]"
puts "REGS_SYNC_ZERO: [get_regs {u_settings_pause_cdc/sync[0]}]"
puts "REGS_SYNC_ZERO_ESC: [get_regs {u_settings_pause_cdc/sync\[0\]}]"
puts "REGS_ALL: [get_regs {u_settings_pause_cdc/*}]"
