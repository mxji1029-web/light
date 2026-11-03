# Read-only reproduction of the physical constraint import context.
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db ../syn_1/HDMI1.4b_Transmitter_v1.0_gate.db
clear_sdc -user
read_adc ../../../user_source/constraints_source/pin.adc
read_sdc D:/FPGA/competition/03_dev/oral_album_lyrics28/backups/20261022_before_picture_controls/timing.sdc
puts "PROBE_CLOCK: [get_clocks {video_clk}]"
puts "PROBE_PINS: [get_pins {u_settings_pause_cdc/*}]"
puts "PROBE_DATA: [get_pins {u_settings_pause_cdc/sync_reg*.d}]"
puts "BEFORE_PLACE_REGS: [get_regs {u_settings_pause_cdc/*}]"
puts "BEFORE_PLACE_FIRST_STAGE: [get_regs {u_settings_pause_cdc/sync[0]}]"
read_sdc D:/FPGA/competition/03_dev/oral_album_lyrics28/tools/probe_settings_first_stage.sdc
puts "PROBE_FINISHED"
commit_param -step place
place
update_timing -mode manhattan
puts "AFTER_PLACE_CLOCK: [get_clocks {video_clk}]"
puts "AFTER_PLACE_PINS: [get_pins {u_settings_pause_cdc/*}]"
set settings_packed_d [get_pins {u_settings_pause_cdc/*.mi*}]
puts "PACKED_DATA_COUNT: [llength $settings_packed_d]"
puts "PACKED_DATA_PINS: $settings_packed_d"
if {[llength $settings_packed_d] != 2} {error "Expected packed data pins of the two-stage synchronizer"}
report_timing_summary -file probe_settings_timing.rpt
puts "AFTER_PLACE_REGS: [get_regs {u_settings_pause_cdc/*}]"
set settings_first [get_regs {u_settings_pause_cdc/sync[0]}]
puts "AFTER_PLACE_FIRST_STAGE: $settings_first"
if {[llength $settings_first] != 1} {error "First-stage register collection must be unique"}
report_timing_path -from [get_regs {u_settings_pause_cdc/sync[0]}] -to [get_regs {u_settings_pause_cdc/sync[1]}] -file probe_settings_internal.rpt
