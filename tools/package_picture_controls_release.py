"""Freeze the verified extension04 build; never touches TF or the development board."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY, SYN = RUNS / 'phy_1', RUNS / 'syn_1'
OUT = ROOT / 'release/20261022_picture_controls'
bit = PHY / 'HDMI1.4b_Transmitter_v1.0.bit'
sdc = ROOT / 'proj/src/user_source/constraints_source/timing.sdc'
log = (PHY / 'build_picture_controls.log').read_text(errors='replace')
timing = (PHY / 'final_timing.rpt').read_text(errors='replace')
area = (PHY / 'HDMI1.4b_Transmitter_v1.0_phy.area').read_text(errors='replace')
internal = (PHY / 'settings_sync_internal.rpt').read_text(errors='replace')
regression = ROOT / 'sim/20261022_picture_controls_regression.log'
assert 'ALL PASS: 45 RTL cases plus independent exact OSD labels' in regression.read_text(errors='replace')
assert 'USR-8159' not in log and 'No pins matched' not in log, 'Constraint failed or unmatched'
assert 'finish command "bitgen' in log, 'No completed bitgen'
assert bit.stat().st_mtime > sdc.stat().st_mtime, 'Bit predates final SDC'
assert bit.stat().st_size == 670364
assert 'get_regs {u_settings_pause_cdc/sync[0]}' in sdc.read_text(encoding='utf-8')
setup, stns = map(float, re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns', timing).groups())
hold, htns = map(float, re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns', timing).groups())
assert hold >= 0 and htns == 0, 'Hold timing not clean'
video_block = timing.split('Path Group     :     video_clk -> video_clk', 1)[1]
video_setup = float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns', video_block).group(1))
assert video_setup > 0
assert 'Path Group     :     video_clk -> clk' not in timing
assert 'Path Group     :     clk -> clk' in internal
assert 'u_settings_pause_cdc/sync[0]' in internal and 'u_settings_pause_cdc/sync[1]' in internal
assert re.search(r'Min\s*: HWNS\s+[\d.]+ns, HTNS\s+0.000ns,\s+0 Viol', internal)
resources = {name: int(re.search(r'^#' + tag + r'\s+(\d+)\s+out of', area, re.M).group(1))
             for name, tag in [('lut', 'lut'), ('register', 'reg'), ('bram9k', 'bram'), ('dsp', 'dsp'), ('pll', 'pll')]}
digest = hashlib.sha256(bit.read_bytes()).hexdigest()
OUT.mkdir(exist_ok=False)

def copy(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

copy(bit, OUT / 'oral_album_picture_controls.bit')
for source, name in [(PHY/'build_picture_controls.log', 'build.log'),
                     (SYN/'synthesis_picture_controls.log', 'synthesis.log'),
                     (PHY/'final_timing.rpt', 'final_timing.rpt'),
                     (PHY/'settings_sync_internal.rpt', 'settings_sync_internal.rpt'),
                     (PHY/'HDMI1.4b_Transmitter_v1.0_phy.area', 'resource.area'),
                     (PHY/'route.qor', 'route.qor'),
                     (PHY/'probe_settings_constraints.log', 'constraint_probe.log'),
                     (regression, 'regression.log'),
                     (ROOT/'material/picture_settings_20261022/rom_verification.log', 'rom_verification.log')]:
    copy(source, OUT/name)
for name in ['normal.png', 'brightness.png', 'contrast.png', 'comparison.png', 'preview.gif', 'font_atlas.png', 'font_manifest.json', 'font.hex']:
    copy(ROOT/'material/picture_settings_20261022'/name, OUT/'preview'/name)
# Audit snapshot; use the existing TD project at its original location to build.
shutil.copytree(ROOT/'proj/src/user_source', OUT/'source/proj/src/user_source')
for relative in ['proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al',
                 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0.prj',
                 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0.prj',
                 'sim/run_tests.ps1', 'sim/tb_picture_controls.v', 'sim/tb_photo_adjust.v',
                 'sim/tb_picture_settings_osd.v', 'sim/tb_picture_pipeline.v',
                 'tools/build_phy.tcl', 'tools/build_picture_settings_font.py',
                 'tools/check_picture_settings_raster.py', 'tools/package_picture_settings_preview.py',
                 'tools/probe_settings_constraints.tcl', 'tools/probe_settings_first_stage.sdc',
                 'tools/package_picture_controls_release.py']:
    copy(ROOT/relative, OUT/'source'/relative)
hashes = {str(path.relative_to(OUT/'source')).replace('\\','/'): hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted((OUT/'source').rglob('*')) if path.is_file()}
(OUT/'source_sha256.json').write_text(json.dumps(hashes, indent=2, ensure_ascii=False), encoding='utf-8')
manifest = dict(built_on='2026-10-22', target='EG4S20BG256/HX4S20C', bitstream='oral_album_picture_controls.bit',
                bytes=bit.stat().st_size, sha256=digest, rtl_tests=45,
                default_identity_pixels=307200, pipeline_pixels=921600,
                independent_osd_frame_pixels=1228800, independent_osd_photo_panel_pixels=46080,
                resources=resources, setup_wns_ns=setup, setup_tns_ns=stns, hold_wns_ns=hold,
                hold_tns_ns=htns, video_domain_setup_wns_ns=video_setup,
                hardware_download_performed=False, tf_modified=False, hardware_test_pending=True,
                final_independent_agent_review_complete=False)
(OUT/'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
readme = f'''# 扩展04：实时亮度/对比度与中文OSD

下载文件：{OUT.as_posix()}/oral_album_picture_controls.bit

大小：{bit.stat().st_size}字节；SHA256：{digest.upper()}。

## 按键操作

按开发板丝印 KEY2/KEY3/KEY4 操作。进入调节前，建议先关闭自动轮播，方便比较同一张照片。

| 操作 | 正常播放 | 调节模式 |
| --- | --- | --- |
| KEY3 长按约1秒后松开 | 进入调节 | 退出调节并保留参数 |
| KEY3 短按后松开 | 暂停/继续音乐及歌词 | 切换亮度/对比度，箭头指向当前项 |
| KEY2 短按 | 下一张照片 | 当前参数减一档 |
| KEY4 短按 | 自动轮播开/关 | 当前参数加一档 |
| KEY1 复位 | 整个系统复位 | 整个系统复位，恢复亮度0/对比度100% |

亮度−64～+64，每档8；对比度50/75/100/125/150%。按键每按一次一档；长按不连加。长按KEY3不会同时触发暂停。

左上角中文面板显示“画面调节”、实际亮度、对比度和选中箭头；退出后隐藏面板，效果保留，断电或复位后回到默认。参数在下一帧生效，防止一帧上下亮度不同。只处理照片/转场，歌词和音频波形保持各自颜色。

进入调节模式只屏蔽KEY2/KEY4的切图/轮播按键功能，原先已开启的自动轮播仍会继续；需固定照片时先在正常模式按KEY4关闭轮播。

## TD下载步骤

1. TF卡保持现有18张照片和歌曲，不需插电脑、复制文件或改素材。插入开发板，连接HDMI_B、供电和下载线。
2. TD → Tools → BitWriter。选择EG4S20BG256，操作PROGRAM_SRAM，下载频率1 MHz。
3. Add File选择本目录 oral_album_picture_controls.bit，选中该行后Run。
4. 等待 PROGRAM_SRAM success 和首张照片；先检查音乐、歌词、波形及切图仍正常。
5. 长按KEY3约1秒进入；KEY4连续按4次，应显示亮度+32并变亮。KEY3短按改选对比度，KEY4增加到125%。
6. 长按KEY3退出，面板消失且效果保留；再进入确认参数仍在。正常模式KEY3短按应仍暂停/继续，不能被长按误触发。
7. KEY1复位后，应回到亮度0、对比度100%及正常播放模式。低亮/高亮和50%/150%也应可到达边界，无数值溢出或画面撕裂。

本次只准备文件，由你下载；未操作板子、未固化Flash。PROGRAM_SRAM断电后丢失。

## 验证和限制

45项RTL回归通过；默认307200照片像素与旧版逐一相同；完整按键/照片/歌词/波形/OSD链路921600像素检查通过。OSD另经独立图像模型核对1228800帧像素和46080真实照片面板像素，涵盖符号、数字、全部五档对比度和箭头。

TD综合、布局布线、bitgen完成。LUT {resources['lut']}/19600、寄存器 {resources['register']}/19600、BRAM {resources['bram9k']}/64、DSP {resources['dsp']}/29、PLL {resources['pll']}/4。视频同域Setup WNS +{video_setup:.3f} ns；全局Hold WNS +{hold:.3f} ns、TNS {htns:.3f} ns。暂停跨时钟仅排除video_clk到首级sync[0]的入口；第二级仍按50MHz正常检查，报告见settings_sync_internal.rpt。

工程仍有既有全局Setup违例：WNS {setup:.3f} ns、TNS {stns:.3f} ns；未宣称全局时序收敛。新版按键和视觉效果需要你实板验收。preview里的图片/动画来自实际生产RTL仿真，不是实板录像。source为审阅快照，编译仍使用原工程目录。

## 回退

上一版波形增强位流：{ROOT.as_posix()}/release/20261022_waveform_large/oral_album_waveform_large.bit

回退SHA256：62CFFA8B94FE36F2FEE0F70BFB81B432A7E4DBF069F14D9262E636A132BE6BA4。TF素材通用。
'''
(OUT/'上板说明.md').write_text(readme, encoding='utf-8')
print(json.dumps(manifest, indent=2, ensure_ascii=False))
print(f'FROZEN {OUT} with {len(hashes)} source files; no TF/board operation')
