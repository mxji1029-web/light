# Place, route and generate the bitstream for the 28 s lyric demo.
#
# Run from proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1:
#   D:\Anlogic\bin\td_commands_prompt.exe D:/FPGA/.../tools/build_phy.tcl
# (forward slashes: TD passes the argument through Tcl, "\t" would become a tab)
#
# Why this is not just "source DefaultFlow.tcl":
#   * the ADC/SDC are re-read explicitly, so an edited SDC is never masked by
#     the constraints stored inside gate.db;
#   * TD 6.2 crashes (coredump) in the hold-fix ECO that runs inside "route"
#     for this netlist, both with the original and the CDC-constrained SDC.
#     The vendor flow's own alternative branch is used instead: route with
#     fix_hold off, then run fix_hold as a standalone command. Measured with
#     the standard flow: crash after "Stage 3 | Hold Fix"; with this split:
#     route + fix_hold both finish and bitgen succeeds.
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db ../syn_1/HDMI1.4b_Transmitter_v1.0_gate.db
clear_sdc -user
read_adc ../../../user_source/constraints_source/pin.adc
read_sdc ../../../user_source/constraints_source/timing.sdc

commit_param -step place
place
update_timing -mode manhattan
set bmp_ack_meta [get_regs {sd_card_bmp_m0/bmp_read_m0/write_ack_meta}]
set bmp_ack_sync [get_regs {sd_card_bmp_m0/bmp_read_m0/write_ack_sync}]
puts "BMP_ACK_META_COUNT: [llength $bmp_ack_meta]"
if {[llength $bmp_ack_meta]!=1 || [llength $bmp_ack_sync]!=1} {error "BMP ACK synchronizer stage mapping is not unique"}
foreach pause_reg {pause_audio_meta pause_audio_sync sd_card_bmp_m0/pause_sd_meta sd_card_bmp_m0/pause_sd_sync} {
    set pause_stage [get_regs $pause_reg]
    puts "PLAYBACK_STAGE: $pause_reg COUNT: [llength $pause_stage]"
    if {[llength $pause_stage]!=1} {error "Playback synchronizer stage mapping is not unique: $pause_reg"}
}
report_timing_summary -file HDMI1.4b_Transmitter_v1.0_place.timing
report_area -io_info -file HDMI1.4b_Transmitter_v1.0_phy.area
flow_status -file place_flow.status
export_db HDMI1.4b_Transmitter_v1.0_place.db

commit_param -step route
set_param route fix_hold off
route
set_param route fix_hold on
fix_hold
report_abnormal_timing_target -file abnormal_timing.rpt
report_qor -step route -file route.qor
report_area -io_info -file HDMI1.4b_Transmitter_v1.0_phy.area
update_timing -mode final
report_timing_status -file HDMI1.4b_Transmitter_v1.0_phy.ts
report_timing_summary -file final_timing.rpt
report_timing_path -from [get_regs {sd_card_bmp_m0/bmp_read_m0/write_ack_meta}] -to [get_regs {sd_card_bmp_m0/bmp_read_m0/write_ack_sync}] -file bmp_ack_internal.rpt
report_timing_path -from [get_regs {pause_audio_meta}] -to [get_regs {pause_audio_sync}] -file pause_audio_internal.rpt
report_timing_path -from [get_regs {sd_card_bmp_m0/pause_sd_meta}] -to [get_regs {sd_card_bmp_m0/pause_sd_sync}] -file pause_sd_internal.rpt
report_timing_exception -file HDMI1.4b_Transmitter_v1.0_exception.timing
flow_status -file route_flow.status
export_db HDMI1.4b_Transmitter_v1.0_pr.db

commit_param -step bitgen
bitgen -bit HDMI1.4b_Transmitter_v1.0.bit
setup_debugger
export_bitgen_param -file .bitgen_param.f
export_flow_status -s opt_place -e bitgen
