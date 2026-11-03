$ErrorActionPreference = 'Stop'
$rtl = Join-Path $PSScriptRoot '../proj/src/user_source/hdl_source'
$iverilog = 'D:\iverilog\bin\iverilog.exe'
$vvp = 'D:\iverilog\bin\vvp.exe'
# Keep legacy16 numerical/raster references and the default32 production path
# in the same compile closure. Tests choose their intended mode explicitly.
$spectrumQualitySources = @("$rtl/audio_spectrum_quality.v", "$rtl/spectrum_fft1024.v", "$rtl/spectrum_complex_ram.v")
$output = Join-Path $env:TEMP ('oral_album_tests_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
& $iverilog -g2012 -s tb_photo_transition -o "$output/transition.vvp" "$PSScriptRoot/tb_photo_transition.v" "$rtl/photo_transition.v"
if ($LASTEXITCODE -ne 0) { throw 'Transition compilation failed' }
& $vvp "$output/transition.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Transition regression failed' }
foreach ($samples in @(3, 248, 249, 256, 511, 1441)) {
    & $iverilog -g2012 -s tb_pcm_sd_reader "-Ptb_pcm_sd_reader.SAMPLE_COUNT=$samples" -o "$output/reader.vvp" "$PSScriptRoot/tb_pcm_sd_reader.v" "$rtl/pcm_sd_reader.v"
    if ($LASTEXITCODE -ne 0) { throw 'PCM compilation failed' }
    & $vvp "$output/reader.vvp"
    if ($LASTEXITCODE -ne 0) { throw "PCM regression failed: $samples samples" }
}
Write-Output 'ALL PASS: transition + six PCM boundary/loop cases'
foreach ($test in @('pcm_mix16','voice_rom_player','pcm_player_i2s')) {
    $sources = @("$PSScriptRoot/tb_$test.v", "$rtl/$test.v")
    if ($test -eq 'pcm_player_i2s') { $sources += "$rtl/pcm_mix16.v", "$rtl/I2S_receiver.v" }
    & $iverilog -g2012 -s "tb_$test" -o "$output/$test.vvp" @sources
    if ($LASTEXITCODE -ne 0) { throw "AV compilation failed: $test" }
    & $vvp "$output/$test.vvp"
    if ($LASTEXITCODE -ne 0) { throw "AV regression failed: $test" }
}
Write-Output 'ALL PASS: 10 cases including display event, ROM voice and decoded I2S mixing'

& $iverilog -g2012 -s tb_catalog_scan -o "$output/catalog.vvp" "$PSScriptRoot/tb_catalog_scan.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v"
if ($LASTEXITCODE -ne 0) { throw 'Catalog compile failed' }
& $vvp "$output/catalog.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Catalog scan test failed' }
& $iverilog -g2012 -i -s tb_album_navigation -o "$output/navigation.vvp" "$PSScriptRoot/tb_album_navigation.v" "$rtl/SD/sd_card_bmp.v" "$rtl/pcm_sd_reader.v" "$rtl/pcm_sd_arbiter.v"
if ($LASTEXITCODE -ne 0) { throw 'Navigation compile failed' }
& $vvp "$output/navigation.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Navigation test failed' }
# The board build uses the ALY1 magic (0x31594C41) so the lyric catalog can sit
# next to the untouched ALB1 ALBUM.IDX; re-run the same testbench with that magic.
& $iverilog -g2012 -s tb_catalog_scan "-Ptb_catalog_scan.MAGIC=32'h31594c41" -o "$output/catalog_aly1.vvp" "$PSScriptRoot/tb_catalog_scan.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v"
if ($LASTEXITCODE -ne 0) { throw 'ALY1 catalog compile failed' }
& $vvp "$output/catalog_aly1.vvp"
if ($LASTEXITCODE -ne 0) { throw 'ALY1 catalog test failed' }
Write-Output 'ALL PASS: 13 cases, including catalog validation, ALY1 magic and 64-picture navigation'

# 28 s lyric demonstration: sample-clock advance/freeze, CDC snapshot and overlay pipeline.
& $iverilog -g2012 -s tb_lyric_audio_state -o "$output/lyric_audio_state.vvp" "$PSScriptRoot/tb_lyric_audio_state.v" "$rtl/lyric_audio_state.v"
if ($LASTEXITCODE -ne 0) { throw 'Lyric audio state compile failed' }
& $vvp "$output/lyric_audio_state.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Lyric audio state test failed' }
& $iverilog -g2012 -s tb_lyric_cdc -o "$output/lyric_cdc.vvp" "$PSScriptRoot/tb_lyric_cdc.v" "$rtl/lyric_state_cdc.v"
if ($LASTEXITCODE -ne 0) { throw 'Lyric CDC compile failed' }
& $vvp "$output/lyric_cdc.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Lyric CDC test failed' }
& $iverilog -g2012 -s tb_lyric_overlay -o "$output/lyric_overlay.vvp" "$PSScriptRoot/tb_lyric_overlay.v" "$rtl/lyric_overlay.v" "$rtl/lyric_line_lookup.v"
if ($LASTEXITCODE -ne 0) { throw 'Lyric overlay compile failed' }
& $vvp "$output/lyric_overlay.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Lyric overlay test failed' }
& $iverilog -g2012 -s tb_lyric_lines -o "$output/lyric_lines.vvp" "$PSScriptRoot/tb_lyric_lines.v" "$rtl/lyric_line_lookup.v"
if ($LASTEXITCODE -ne 0) { throw 'Lyric sentence table compile failed' }
& $vvp "$output/lyric_lines.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Lyric sentence table test failed' }
Write-Output 'ALL PASS: 17 RTL cases including the three lyric modules, the sentence table and the ALY1 catalog'

# Board-level picture switching: real sd_card_bmp / bmp_read / arbiter /
# photo_transition with the SPI layer replaced by sim/sd_card_stub.v.
& $iverilog -g2012 -DTB_FAKE_SD -s tb_board_switch -o "$output/board_switch.vvp" "$PSScriptRoot/tb_board_switch.v" "$PSScriptRoot/sd_card_stub.v" "$rtl/SD/sd_card_bmp.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v" "$rtl/pcm_sd_reader.v" "$rtl/pcm_sd_arbiter.v" "$rtl/photo_transition.v"
if ($LASTEXITCODE -ne 0) { throw 'Board switch compile failed' }
& $vvp "$output/board_switch.vvp"
if ($LASTEXITCODE -ne 0) { throw 'Board switch test failed' }
Write-Output 'ALL PASS: 18 RTL cases including catalog-driven KEY2/KEY4 switching'

# Asset-level check: PCM header, glyph/event ROM images, sentence windows, RTL sync.
$python = 'C:\Users\季明鑫\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if (-not (Test-Path $python)) { $python = 'python' }
& $python (Join-Path $PSScriptRoot '../tools/verify_lyric_assets.py')
if ($LASTEXITCODE -ne 0) { throw 'Lyric asset verification failed' }

# First-pair particle reveal: source addresses, production VS, commit protection,
# and production frame-request/video-delay integration under write competition.
foreach ($test in @('particle_read','transition_real_vs','commit_guard','particle_pipeline')) {
    $sources=@("$PSScriptRoot/tb_$test.v")
    switch($test){
      'particle_read' { $sources+="$rtl/SD/frame_fifo_read.v" }
      'transition_real_vs' { $sources+="$rtl/photo_transition.v","$rtl/SD/color_bar.v" }
      'commit_guard' { $sources+="$rtl/SD/sd_card_bmp.v","$rtl/pcm_sd_reader.v","$rtl/pcm_sd_arbiter.v" }
      'particle_pipeline' { $sources+="$rtl/photo_transition.v","$rtl/SD/frame_fifo_read.v","$rtl/SD/video_delay.v","$rtl/SD/video_timing_data.v","$rtl/SD/color_bar.v" }
    }
    & $iverilog -g2012 -i -I "$rtl/SD" -s "tb_$test" -o "$output/$test.vvp" @sources
    if ($LASTEXITCODE -ne 0) { throw "Particle compile failed: $test" }
    & $vvp "$output/$test.vvp"
    if ($LASTEXITCODE -ne 0) { throw "Particle regression failed: $test" }
}
Write-Output 'ALL PASS: 22 RTL cases and full-song assets; first pair only, no transition backdrop'

# Curated multi-transition extension (legacy defaults above remain covered).
& $python -X utf8 (Join-Path $PSScriptRoot '../tools/build_multi_transition_oracle.py')
if($LASTEXITCODE -ne 0){throw 'Independent multi-transition oracle failed'}
& $iverilog -g2012 -s tb_transition_masks -o "$output/masks.vvp" "$PSScriptRoot/tb_transition_masks.v" "$rtl/transition_mask.v"
if($LASTEXITCODE -ne 0){throw 'Mask compilation failed'}
& $vvp "$output/masks.vvp"
if($LASTEXITCODE -ne 0){throw 'Mask endpoint/geometry test failed'}
& $iverilog -g2012 -s tb_multi_transition_control -o "$output/multi_control.vvp" "$PSScriptRoot/tb_multi_transition_control.v" "$rtl/photo_transition.v"
if($LASTEXITCODE -ne 0){throw 'Multi-control compile failed'}
& $vvp "$output/multi_control.vvp"
if($LASTEXITCODE -ne 0){throw 'Multi-control sequence failed'}
foreach($style in 0..11){
 & $iverilog -g2012 -I "$rtl/SD" -s tb_particle_pipeline "-Ptb_particle_pipeline.STYLE_TO_TEST=$style" "-Ptb_particle_pipeline.MULTI_TEST=1" -o "$output/multi_pipeline.vvp" "$PSScriptRoot/tb_particle_pipeline.v" "$rtl/photo_transition.v" "$rtl/transition_mask.v" "$rtl/SD/frame_fifo_read.v" "$rtl/SD/video_delay.v" "$rtl/SD/video_timing_data.v" "$rtl/SD/color_bar.v"
 if($LASTEXITCODE -ne 0){throw "Style $style pipeline compile failed"}
 & $vvp "$output/multi_pipeline.vvp"
 if($LASTEXITCODE -ne 0){throw "Style $style pipeline failed"}
}
Write-Output 'ALL PASS: 36 RTL cases and full-song assets; 12 distinct transition geometries'

# Motion comfort and independent, complete-frame glyph placement regression.
foreach($test in @('lyric_motion','lyric_raster')){
 & $iverilog -g2012 -s "tb_$test" -o "$output/$test.vvp" "$PSScriptRoot/tb_$test.v" "$rtl/lyric_overlay.v" "$rtl/lyric_line_lookup.v"
 if($LASTEXITCODE -ne 0){throw "Caption compile failed: $test"}
 # The raster checker consumes this testbench's output from sim/.
 Push-Location $PSScriptRoot
 try{ & $vvp "$output/$test.vvp"; if($LASTEXITCODE -ne 0){throw "Caption test failed: $test"} }
 finally{ Pop-Location }
}
& $python -X utf8 (Join-Path $PSScriptRoot '../tools/check_lyric_raster.py') --gentle
if($LASTEXITCODE -ne 0){throw 'Caption duplicate/ghost pixel check failed'}
Write-Output 'ALL PASS: 38 RTL cases, full-song assets and 1,843,200 independently checked caption pixels'

& $python -X utf8 (Join-Path $PSScriptRoot '../tools/build_spectrum_vectors.py') --check
if($LASTEXITCODE -ne 0){throw 'Independent spectrum/DFT oracle failed'}
foreach($test in @('spectrum_baseline','spectrum_bins','spectrum_raster','spectrum_i2s')){
 $sources=@("$PSScriptRoot/tb_$test.v","$rtl/audio_waveform_overlay.v") + $spectrumQualitySources
 if($test -eq 'spectrum_i2s'){$sources+="$rtl/pcm_player_i2s.v","$rtl/pcm_mix16.v","$rtl/I2S_receiver.v"}
 & $iverilog -g2012 -s "tb_$test" -o "$output/$test.vvp" @sources
 if($LASTEXITCODE -ne 0){throw "Waveform compilation failed: $test"}
 Push-Location $PSScriptRoot
 try { & $vvp "$output/$test.vvp"; if($LASTEXITCODE -ne 0){throw "Spectrum regression failed: $test"} }
 finally { Pop-Location }
}
Write-Output 'ALL PASS: 42 RTL cases; legacy16 direct DFT/464 magnitudes and real I2S references, default32 silent baseline, 921600 raster pixels'

foreach($test in @('picture_controls','photo_adjust','picture_settings_osd')){
 $unit=if($test -eq 'picture_controls'){'picture_controls'}elseif($test -eq 'photo_adjust'){'photo_adjust'}else{'picture_settings_osd'}
 & $iverilog -g2012 -s "tb_$test" -o "$output/$test.vvp" "$PSScriptRoot/tb_$test.v" "$rtl/$unit.v"
 if($LASTEXITCODE -ne 0){throw "Settings compile failed: $test"}
 Push-Location $PSScriptRoot
 try{ & $vvp "$output/$test.vvp"; if($LASTEXITCODE -ne 0){throw "Settings regression failed: $test"} }
 finally{ Pop-Location }
}
Write-Output 'ALL PASS: 45 RTL cases; no-pause short KEY3, settings keys, frame-coherent photo adjustment and bounded Chinese OSD'

$preview=Join-Path $PSScriptRoot '../material/picture_settings_20261022'
New-Item -ItemType Directory -Path $preview -Force | Out-Null
& $iverilog -g2012 -s tb_picture_pipeline -o "$output/picture_pipeline.vvp" "$PSScriptRoot/tb_picture_pipeline.v" "$rtl/picture_controls.v" "$rtl/photo_adjust.v" "$rtl/picture_settings_osd.v" "$rtl/lyric_overlay.v" "$rtl/lyric_line_lookup.v" "$rtl/audio_waveform_overlay.v" @spectrumQualitySources
if($LASTEXITCODE -ne 0){throw 'Full picture pipeline compile failed'}
Push-Location $preview
try{ & $vvp "$output/picture_pipeline.vvp"; if($LASTEXITCODE -ne 0){throw 'Full picture pipeline failed'} }
finally{ Pop-Location }
& $python -X utf8 (Join-Path $PSScriptRoot '../tools/check_picture_settings_raster.py')
if($LASTEXITCODE -ne 0){throw 'Independent settings labels/layout check failed'}
Write-Output 'ALL PASS: 46 RTL cases plus direct DFT spectrum, independent exact OSD labels and complete picture-control default identity'

# Optimization equivalence: unchanged spectrum mapping, catalog edge counts,
# held ACK clock crossing, and cycle-exact FIFO arbitration vs frozen RTL.
& $iverilog -g2012 -s tb_spectrum_height -o "$output/height.vvp" "$PSScriptRoot/tb_spectrum_height.v" "$rtl/audio_waveform_overlay.v" @spectrumQualitySources
if($LASTEXITCODE -ne 0){throw 'Height equivalence compilation failed'}
& $vvp "$output/height.vvp"
if($LASTEXITCODE -ne 0){throw 'Height equivalence failed'}
foreach($count in @(1,2,3,18,63)){
 & $iverilog -g2012 -i -s tb_album_navigation "-Ptb_album_navigation.IMAGE_COUNT=$count" -o "$output/catalog_$count.vvp" "$PSScriptRoot/tb_album_navigation.v" "$rtl/SD/sd_card_bmp.v" "$rtl/pcm_sd_reader.v" "$rtl/pcm_sd_arbiter.v"
 if($LASTEXITCODE -ne 0){throw 'Catalog count compile failed'}
 & $vvp "$output/catalog_$count.vvp"
 if($LASTEXITCODE -ne 0){throw 'Catalog count test failed'}
}
& $iverilog -g2012 -s tb_bmp_ack_cdc -o "$output/ack.vvp" "$PSScriptRoot/tb_bmp_ack_cdc.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v"
if($LASTEXITCODE -ne 0){throw 'BMP ACK CDC compile failed'}
& $vvp "$output/ack.vvp"
if($LASTEXITCODE -ne 0){throw 'BMP ACK CDC failed'}
foreach($burst in @(16,128,256)){
 & $iverilog -g2012 -s tb_write_fifo_equivalence "-Ptb_write_fifo_equivalence.BURST=$burst" -o "$output/write_equiv_$burst.vvp" "$PSScriptRoot/tb_write_fifo_equivalence.v" "$PSScriptRoot/reference/frame_fifo_write_before_opt.v" "$rtl/SD/frame_fifo_write.v"
 if($LASTEXITCODE -ne 0){throw 'FIFO equivalence compile failed'}
 & $vvp "$output/write_equiv_$burst.vvp"
 if($LASTEXITCODE -ne 0){throw 'FIFO cycle equivalence failed'}
}
foreach($addressBits in @(9,12)){
 & $iverilog -g2012 -s tb_write_fifo_equivalence "-Ptb_write_fifo_equivalence.ADDR=$addressBits" -o "$output/write_equiv_addr$addressBits.vvp" "$PSScriptRoot/tb_write_fifo_equivalence.v" "$PSScriptRoot/reference/frame_fifo_write_before_opt.v" "$rtl/SD/frame_fifo_write.v"
 if($LASTEXITCODE -ne 0){throw 'Generic FIFO equivalence compile failed'}
 & $vvp "$output/write_equiv_addr$addressBits.vvp"
 if($LASTEXITCODE -ne 0){throw 'Generic FIFO wrap/width equivalence failed'}
}
Write-Output 'ALL PASS: 58 RTL configurations; exact height, full-width catalog prefetch, ACK CDC and FIFO cycle equivalence'

# APUG092 video contract: one-clock RGB/DE alignment, SOF and 640th-pixel TLAST.
& $iverilog -g2012 -s tb_video_rgb_to_axis_640x480 -o "$output/video_axis.vvp" "$PSScriptRoot/tb_video_rgb_to_axis_640x480.v" "$rtl/video_rgb_to_axis_640x480.v"
if($LASTEXITCODE -ne 0){throw 'Video AXIS contract compilation failed'}
& $vvp "$output/video_axis.vvp"
if($LASTEXITCODE -ne 0){throw 'Video AXIS contract regression failed'}
Write-Output 'ALL PASS: 59 RTL configurations; full-frame APUG092 video contract included'

# Global transport: actual production top wiring with external hard IP omitted.
$transport=@('top_tf_hdmi_audio','picture_controls','photo_transition','pcm_player_i2s','pcm_mix16','I2S_receiver','lyric_audio_state','lyric_state_cdc','lyric_overlay','lyric_line_lookup','photo_adjust','picture_settings_osd','audio_waveform_overlay','video_rgb_to_axis_640x480','audio_spectrum_quality','spectrum_fft1024','spectrum_complex_ram','audio_volume_control','playback_status_cdc','playback_status_osd') | ForEach-Object { "$rtl/$_.v" }
& $iverilog -g2012 -i -s tb_top_playback_pause -o "$output/top_pause.vvp" "$PSScriptRoot/tb_top_playback_pause.v" @transport
if($LASTEXITCODE -ne 0){throw 'Production playback control compile failed'}
& $vvp "$output/top_pause.vvp"
if($LASTEXITCODE -ne 0){throw 'Production playback control regression failed'}
& $iverilog -g2012 -i -s tb_album_pause -o "$output/album_pause.vvp" "$PSScriptRoot/tb_album_pause.v" "$rtl/SD/sd_card_bmp.v" "$rtl/pcm_sd_reader.v" "$rtl/pcm_sd_arbiter.v"
if($LASTEXITCODE -ne 0){throw 'Album pause compile failed'}
& $vvp "$output/album_pause.vvp"
if($LASTEXITCODE -ne 0){throw 'Album pause timer regression failed'}
& $iverilog -g2012 -s tb_spectrum_pause -o "$output/spectrum_pause.vvp" "$PSScriptRoot/tb_spectrum_pause.v" "$rtl/audio_waveform_overlay.v" "$rtl/pcm_player_i2s.v" "$rtl/pcm_mix16.v" "$rtl/I2S_receiver.v" @spectrumQualitySources
if($LASTEXITCODE -ne 0){throw 'Spectrum pause compile failed'}
Push-Location $PSScriptRoot
try{ & $vvp "$output/spectrum_pause.vvp"; if($LASTEXITCODE -ne 0){throw 'Spectrum pause regression failed'} }
finally{ Pop-Location }
foreach($case in @(@(320,240,0,54,0,0),@(800,600,0,54,0,0),@(321,241,1,1027,1,0),@(640,480,0,54,0,0),@(1024,1024,1,65535,0,1),@(1,1,1,511,0,1),@(17,13,1,499,1,1))){
 $params=@("-Ptb_bmp_scaling.QUALITY=0","-Ptb_bmp_scaling.SW=$($case[0])","-Ptb_bmp_scaling.SH=$($case[1])","-Ptb_bmp_scaling.TOP_DOWN=$($case[2])","-Ptb_bmp_scaling.OFFSET=$($case[3])","-Ptb_bmp_scaling.GAPPED=$($case[4])","-Ptb_bmp_scaling.END_WITH_DATA=$($case[5])")
 & $iverilog -g2012 -s tb_bmp_scaling @params -o "$output/bmp_scaling.vvp" "$PSScriptRoot/tb_bmp_scaling.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v"
 if($LASTEXITCODE -ne 0){throw 'BMP scaling compilation failed'}
 & $vvp "$output/bmp_scaling.vvp"
 if($LASTEXITCODE -ne 0){throw "BMP scaling pixel regression failed: $case"}
}
& $iverilog -g2012 -s tb_bmp_header_reject -o "$output/header_reject.vvp" "$PSScriptRoot/tb_bmp_header_reject.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v"
if($LASTEXITCODE -ne 0){throw 'BMP header validation compile failed'}
& $vvp "$output/header_reject.vvp"
if($LASTEXITCODE -ne 0){throw 'BMP malformed header rejection failed'}
Write-Output 'ALL PASS: 70 RTL configurations; global transport, spectrum freeze, seven scaling cases and malformed headers included'


# Actual production quality-mode BMP path: independent fit and Q8 pixel oracle.
foreach($case in @(@(320,240,0,54,0,0),@(800,600,0,54,0,0),@(321,241,1,1027,1,0),@(640,480,0,54,0,0),@(1024,1024,1,65535,0,1),@(1,1,1,511,0,1),@(17,13,1,499,1,1),@(240,480,0,54,0,0),@(1024,576,1,54,0,0))){
 $params=@("-Ptb_bmp_scaling.QUALITY=1","-Ptb_bmp_scaling.SW=$($case[0])","-Ptb_bmp_scaling.SH=$($case[1])","-Ptb_bmp_scaling.TOP_DOWN=$($case[2])","-Ptb_bmp_scaling.OFFSET=$($case[3])","-Ptb_bmp_scaling.GAPPED=$($case[4])","-Ptb_bmp_scaling.END_WITH_DATA=$($case[5])")
 & $iverilog -g2012 -s tb_bmp_scaling @params -o "$output/bmp_quality.vvp" "$PSScriptRoot/tb_bmp_scaling.v" "$rtl/SD/bmp_read.v" "$rtl/SD/bmp_scale_stream.v" "$rtl/SD/bmp_scale_quality.v" "$rtl/SD/bmp_bilinear_stream.v"
 if($LASTEXITCODE -ne 0){throw 'Quality BMP compilation failed'}
 & $vvp "$output/bmp_quality.vvp"
 if($LASTEXITCODE -ne 0){throw "Quality BMP pixel regression failed: $case"}
}
Write-Output 'ALL PASS: 79 RTL configurations; nine full-canvas bilinear/aspect-fit production cases included'

# New default32 path is checked separately from the frozen legacy16 goldens.
foreach($test in @('spectrum_quality_display','spectrum_quality_i2s')){
 $sources=@("$PSScriptRoot/tb_$test.v") + $spectrumQualitySources
 if($test -eq 'spectrum_quality_i2s'){
  $sources+="$rtl/audio_waveform_overlay.v","$rtl/pcm_player_i2s.v","$rtl/pcm_mix16.v","$rtl/I2S_receiver.v"
 }
 & $iverilog -g2012 -s "tb_$test" -o "$output/$test.vvp" @sources
 if($LASTEXITCODE -ne 0){throw "Default32 compilation failed: $test"}
 Push-Location $PSScriptRoot
 try{ & $vvp "$output/$test.vvp"; if($LASTEXITCODE -ne 0){throw "Default32 regression failed: $test"} }
 finally{ Pop-Location }
}
Write-Output 'ALL PASS: 81 RTL configurations; legacy16 references retained; default32 band coverage/raster, real I2S peak, no overrun and pause/resume included'

# Deepening regressions use the live production sources and independent exact
# RGB/area oracles. A unique name preserves evidence from every invocation.
$deepeningRun = 'extension_suite_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
& $python -X utf8 (Join-Path $PSScriptRoot '../tools/run_extension_deepening_tests.py') --name $deepeningRun
if($LASTEXITCODE -ne 0){throw 'Production extension integration failed'}
& $python -X utf8 (Join-Path $PSScriptRoot '../material/extension_deepening_20261024/settings_candidate/run_quality.py') --variant live --run-name $deepeningRun --case adjust
if($LASTEXITCODE -ne 0){throw 'Settings exact RGB, restore controls or UI oracle failed'}
& $python -X utf8 (Join-Path $PSScriptRoot '../material/extension_deepening_20261024/transition_candidate/run_quality.py') --variant live --name $deepeningRun
if($LASTEXITCODE -ne 0){throw 'Transition area/duration/pause regression failed'}
& $python -X utf8 (Join-Path $PSScriptRoot '../material/extension_deepening_20261024/subtitle_candidate/run_subtitle_candidate.py') green --live --name $deepeningRun
if($LASTEXITCODE -ne 0){throw 'Subtitle atomic CDC, exact RGB, gradient or shadow regression failed'}
Write-Output 'ALL PASS: baseline81 plus production extension integration, exhaustive settings, eight transition durations and independent subtitle RGB/CDC oracles'
& $python -X utf8 (Join-Path $PSScriptRoot '../tools/run_autoplay_terminal_tests.py') --name $deepeningRun
if($LASTEXITCODE -ne 0){throw 'Autoplay terminal cycle equivalence failed'}
Write-Output 'ALL PASS: six additional exact-cycle autoplay counter/handshake equivalence configurations'

# APUG011 refresh launch regression: starts wait for busy/ref to clear, while
# in-flight bursts continue even when the memory reports their own busy.
& $iverilog -g2012 -s tb_sdram_start_guard -o "$output/sdram_start_guard.vvp" "$PSScriptRoot/tb_sdram_start_guard.sv" "$rtl/SD/frame_fifo_read.v" "$rtl/SD/frame_fifo_write.v"
if($LASTEXITCODE -ne 0){throw 'SDRAM start guard compile failed'}
& $vvp "$output/sdram_start_guard.vvp"
if($LASTEXITCODE -ne 0){throw 'SDRAM start guard contract failed'}
& $python -X utf8 (Join-Path $PSScriptRoot '../material/white_sparkles_20261025/gap_sweep/run_sweep.py') --name ('production_' + $deepeningRun)
if($LASTEXITCODE -ne 0){throw 'Native encrypted SDRAM phase78 failed'}
Write-Output 'ALL PASS: production refresh start contract and78 real encrypted controller phase configurations'

# Live production volume mailbox/ramp and real serial PCM output. Frozen
# constant255 RED evidence is kept separately under material/volume_status.
$volumeTests = Join-Path $PSScriptRoot '../material/volume_status_20261025/audio'
foreach($ratio in @(@(7,11),@(2,19),@(23,3),@(13,17))){
 & $iverilog -g2012 -DCHECK_MAILBOX -s tb_audio_volume_control "-Ptb_audio_volume_control.CONTROL_HALF_NS=$($ratio[0])" "-Ptb_audio_volume_control.AUDIO_HALF_NS=$($ratio[1])" -o "$output/volume_async.vvp" "$volumeTests/tb_audio_volume_control.sv" "$rtl/audio_volume_control.v"
 if($LASTEXITCODE -ne 0){throw 'Volume CDC compile failed'}
 & $vvp "$output/volume_async.vvp"
 if($LASTEXITCODE -ne 0){throw "Volume CDC/ramp regression failed: $ratio"}
}
& $iverilog -g2012 -s tb_audio_volume_i2s -o "$output/volume_i2s.vvp" "$volumeTests/tb_audio_volume_i2s.sv" "$rtl/audio_volume_control.v" "$rtl/pcm_player_i2s.v" "$rtl/pcm_mix16.v" "$rtl/I2S_receiver.v"
if($LASTEXITCODE -ne 0){throw 'Real I2S volume compilation failed'}
& $vvp "$output/volume_i2s.vvp"
if($LASTEXITCODE -ne 0){throw 'Real I2S volume regression failed'}
Write-Output 'ALL PASS: live volume async ratios4 and real I2S default identity, mute and paused ramp'
& $python -X utf8 (Join-Path $PSScriptRoot '../tools/run_live_status_hud_tests.py') --name ('hud_' + $deepeningRun)
if($LASTEXITCODE -ne 0){throw 'Live HUD exact pixels, event timer or CDC regression failed'}
Write-Output 'ALL PASS: live HUD3686400 pixels, timer, independent events and four CDC ratios'
