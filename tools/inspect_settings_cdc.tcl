# Read-only query of the exact new CDC endpoint before adding a narrow exception.
import_db D:/FPGA/competition/03_dev/oral_album_lyrics28/proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0_gate.db
puts "SETTINGS_CDC_PINS: [get_pins {u_settings_pause_cdc/*}]"
set settings_meta [get_pins {u_settings_pause_cdc/sync_reg\[0\].d}]
puts "EXACT_META_COUNT: [llength $settings_meta]"
puts "EXACT_META_PIN: $settings_meta"
if {[llength $settings_meta] != 1} {error "Settings pause CDC first-stage endpoint is not unique"}
set_false_path -to $settings_meta
puts "NARROW_CDC_EXCEPTION_ACCEPTED"
