"""Freeze only a verified build; this script never accesses TF or hardware."""
from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
RUNS=ROOT/'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY=RUNS/'phy_1';SYN=RUNS/'syn_1';MAT=ROOT/'material/spectrum_bars_20261022'
OUT=ROOT/'release/20261022_spectrum_bars'
reg=(ROOT/'sim/20261022_spectrum_bars_regression.log').read_text(errors='replace')
assert 'ALL PASS: 46 RTL cases plus direct DFT spectrum' in reg
log=(PHY/'build_spectrum_bars.log').read_text(errors='replace')
assert 'finish command "bitgen' in log
assert 'USR-8159' not in log and 'No pins matched' not in log
timing=(PHY/'final_timing.rpt').read_text(errors='replace')
setup,stns=map(float,re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns',timing).groups())
hold,htns=map(float,re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns',timing).groups())
video=float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns',timing.split('Path Group     :     video_clk -> video_clk')[1]).group(1))
assert video>0 and hold>=0 and htns==0
area=(PHY/'HDMI1.4b_Transmitter_v1.0_phy.area').read_text(errors='replace')
resources={key:int(re.search(r'^#'+tag+r'\s+(\d+)\s+out of',area,re.M).group(1))
           for key,tag in [('lut','lut'),('register','reg'),('bram9k','bram'),('dsp','dsp'),('pll','pll')]}
assert 'PASS 24 actual' in (MAT/'render.log').read_text()
assert '116496 independently checked' in (MAT/'preview_verification.log').read_text()
assert 'PASS: 8192 glyph rows' in (MAT/'rom_verification.log').read_text()
bit=PHY/'HDMI1.4b_Transmitter_v1.0.bit';data=bit.read_bytes();digest=hashlib.sha256(data).hexdigest()
assert len(data)==670364
OUT.mkdir(exist_ok=False)
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
copy(bit,OUT/'oral_album_spectrum_bars.bit')
for src,name in [(PHY/'build_spectrum_bars.log','build.log'),(PHY/'final_timing.rpt','final_timing.rpt'),
                 (PHY/'HDMI1.4b_Transmitter_v1.0_phy.area','resource.area'),(PHY/'route.qor','route.qor'),
                 (SYN/'synthesis_spectrum_bars.log','synthesis.log'),
                 (ROOT/'sim/20261022_spectrum_bars_regression.log','regression.log'),
                 (MAT/'rom_verification.log','rom_verification.log'),(MAT/'preview_verification.log','preview_verification.log'),
                 (MAT/'render.log','render.log')]:copy(src,OUT/name)
for name in ['preview.png','preview.gif','detail.gif','levels.csv','vectors.json']:
    copy(MAT/name,OUT/'preview'/name)
shutil.copytree(ROOT/'proj/src/user_source',OUT/'source/proj/src/user_source')
relatives=['proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al',
 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0.prj',
 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0.prj',
 'tools/build_phy.tcl','tools/build_spectrum_vectors.py','tools/package_spectrum_preview.py',
 'tools/package_spectrum_release.py','sim/run_tests.ps1','sim/tb_spectrum_baseline.v',
 'sim/tb_spectrum_bins.v','sim/tb_spectrum_raster.v','sim/tb_spectrum_i2s.v','sim/tb_render_spectrum.v',
 'sim/tb_picture_controls.v','sim/tb_picture_pipeline.v']
for relative in relatives:copy(ROOT/relative,OUT/'source'/relative)
hashes={p.relative_to(OUT/'source').as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((OUT/'source').rglob('*')) if p.is_file()}
(OUT/'source_sha256.json').write_text(json.dumps(hashes,indent=2,ensure_ascii=False),encoding='utf-8')
frequencies=json.loads((MAT/'vectors.json').read_text())['frequencies_hz']
m=dict(built_on='2026-10-22',bitstream='oral_album_spectrum_bars.bit',bytes=len(data),sha256=digest,
       target='EG4S20BG256/HX4S20C',spectrum='16 Goertzel frequency points, rectangular1024-sample blocks',
       sample_rate_nominal=48000,frequencies_hz=frequencies,display_rows=[440,478],bar_count=16,
       normal_key3_short_press='no action; playback continuous',rtl_tests=46,resources=resources,
       setup_wns_ns=setup,setup_tns_ns=stns,hold_wns_ns=hold,hold_tns_ns=htns,
       video_domain_setup_wns_ns=video,independent_review_complete=True,
       tf_modified=False,hardware_download_performed=False,hardware_test_pending=True)
(OUT/'manifest.json').write_text(json.dumps(m,indent=2,ensure_ascii=False),encoding='utf-8')
readme=f'''# 底边对齐频谱版（取消KEY3短按暂停）

下载：{OUT.as_posix()}/oral_album_spectrum_bars.bit

{len(data)}字节；SHA256：{digest.upper()}。

## 这版变化

正常播放时短按KEY3不执行操作，歌曲持续播放。KEY3长按约1秒仍进入/退出调节；调节模式里短按KEY3仍选择亮度/对比度，KEY2减、KEY4加，退出保留设置。KEY2正常切图、KEY4轮播开关、KEY1整体复位保持。

底部改为16根向上跳动的暖金色频谱柱，统一底边y478，最高y440，保留歌词间隔。左侧低频、右侧高频；柱体快速上升、每帧最多下降2像素，顶部细线缓降。静音最后只剩底部基线。照片、歌曲和歌词素材不变。

这是从实际HDMI输出PCM计算的16个Goertzel频点幅值，不是按时间排列的波形，也不是完整FFT分带积分。每1024采样更新一组（约21.3ms），16频点约94Hz～18kHz；对数显示兼顾强弱音。采样率实际受原音频PLL影响，频率以48kHz标称列出。

## 下载到板子

1. TF继续用现有18张照片和歌曲，不需插电脑或改素材。连接开发板电源、下载线、HDMI_B。
2. TD → Tools → BitWriter，EG4S20BG256，PROGRAM_SRAM，下载频率1 MHz。
3. Add File选本目录oral_album_spectrum_bars.bit，选中该行，Run；等待PROGRAM_SRAM success。
4. 检查音乐和歌词连续播放；短按KEY3几次，音乐应不中断，歌词与频谱继续走。
5. 长按KEY3约1秒进入调节，短按切换选项，KEY2/KEY4减/加；再次长按退出，音乐仍持续。
6. 检查所有柱体底边对齐、顶部随音频变化，强弱音有差别；歌词与柱条不重叠。声音中低频能量通常更多，各柱不会始终一样高。
7. KEY2切图、KEY4轮播和首次粒子转场应保持原有行为。若要固定一张图调参数，先在普通模式关闭自动轮播。

本轮未下载SRAM、未固化Flash；PROGRAM_SRAM断电后失效。

## 验证和边界

46项RTL回归通过。独立直接DFT核对16单音定位，464组定点幅值/高度逐项一致，包含双音、DC、静音、满幅、噪声和连续8块真实歌曲；真实PCM播放器→I2S接收器→频谱测试通过，无采样丢失。921600频谱像素、完整照片/歌词/调节链路和中文OSD也通过。

preview里的24帧由实际生产RTL按25MHz、800×525、48k采样节奏绘制，116496个着色像素另作独立核对；它是仿真预览，不是实板录像。全部改动已独立只读复核，未发现重要问题。

TD综合、布局布线与bitgen完成。LUT {resources['lut']}/19600、寄存器 {resources['register']}/19600、BRAM {resources['bram9k']}/64、DSP {resources['dsp']}/29、PLL {resources['pll']}/4。视频同域Setup +{video:.3f}ns；全局Hold +{hold:.3f}ns、HTNS0。工程仍有既有全局Setup WNS {setup:.3f}ns/TNS {stns:.3f}ns，未宣称整体时序收敛。新视觉效果和按键行为待你实板验收。

## 回退

上一版调节功能位流：{ROOT.as_posix()}/release/20261022_picture_controls/oral_album_picture_controls.bit

SHA256：4AE7663702E47BDD03544A5DF94469236B6F1400878F10483B6B3BF5F3ACD028。TF通用。source为审阅快照，编译使用原工程目录。
'''
(OUT/'上板说明.md').write_text(readme,encoding='utf-8')
print(json.dumps(m,indent=2,ensure_ascii=False));print(f'FROZEN {OUT}; {len(hashes)} source files')
