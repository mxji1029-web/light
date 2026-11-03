"""Freeze the measured optimization, preserving the confirmed playback release."""
from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
RUNS=ROOT/'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY=RUNS/'phy_1';SYN=RUNS/'syn_1'
PREV=ROOT/'release/20261022_spectrum_bars';OUT=ROOT/'release/20261022_optimized'
MAT=ROOT/'material/spectrum_bars_20261022'
old=json.loads((PREV/'manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256((PREV/old['bitstream']).read_bytes()).hexdigest()==old['sha256']
for relative,digest in json.loads((PREV/'source_sha256.json').read_text(encoding='utf-8')).items():
    assert hashlib.sha256((PREV/'source'/relative).read_bytes()).hexdigest()==digest
reg=ROOT/'sim/20261022_optimized_final_regression.log'
assert 'ALL PASS: 58 RTL configurations' in reg.read_text(errors='replace')
log=(PHY/'build_optimized.log').read_text(errors='replace')
assert 'finish command "bitgen' in log and 'BMP_ACK_META_COUNT: 1' in log
assert 'USR-8159' not in log and 'No pins matched' not in log
timing=(PHY/'final_timing.rpt').read_text(errors='replace')
setup,stns=map(float,re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns',timing).groups())
hold,htns=map(float,re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns',timing).groups())
domains={name:float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns',timing.split(f'Path Group     :     {name} -> {name}')[1]).group(1))
         for name in ['video_clk','sd_card_clk','ext_mem_clk']}
assert hold>=0 and htns==0 and domains['video_clk']>old['video_domain_setup_wns_ns'] and domains['ext_mem_clk']>0
assert domains['sd_card_clk']>0,'SD-side synchronous timing is not closed'
area=(PHY/'HDMI1.4b_Transmitter_v1.0_phy.area').read_text(errors='replace')
resources={key:int(re.search(r'^#'+tag+r'\s+(\d+)\s+out of',area,re.M).group(1))
           for key,tag in [('lut','lut'),('register','reg'),('bram9k','bram'),('dsp','dsp'),('pll','pll')]}
assert all(resources[k]<old['resources'][k] for k in ['lut','register','dsp'])
assert resources['bram9k']<=old['resources']['bram9k']
ack=(PHY/'bmp_ack_internal.rpt').read_text(errors='replace')
assert re.search(r'Min\s*: HWNS\s+[\d.]+ns, HTNS\s+0.000ns,\s+0 Viol',ack)
assert 'PASS: 8192 glyph rows' in (MAT/'rom_optimized_final.log').read_text()
assert 'PASS 24 actual' in (MAT/'render_optimized.log').read_text()
assert (MAT/'levels.csv').read_bytes()==(PREV/'preview/levels.csv').read_bytes()
from PIL import Image
assert Image.open(MAT/'preview.png').tobytes()==Image.open(PREV/'preview/preview.png').tobytes()
bit=PHY/'HDMI1.4b_Transmitter_v1.0.bit';data=bit.read_bytes();digest=hashlib.sha256(data).hexdigest()
assert len(data)==670364
OUT.mkdir(exist_ok=False)
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
copy(bit,OUT/'oral_album_optimized.bit')
for src,name in [(PHY/'build_optimized.log','build.log'),(PHY/'final_timing.rpt','final_timing.rpt'),
 (PHY/'HDMI1.4b_Transmitter_v1.0_phy.area','resource.area'),(PHY/'route.qor','route.qor'),
 (PHY/'bmp_ack_internal.rpt','bmp_ack_internal.rpt'),(SYN/'synthesis_optimized.log','synthesis.log'),
 (reg,'regression.log'),(MAT/'rom_optimized_final.log','rom_verification.log'),
 (MAT/'render_optimized.log','render.log'),(MAT/'preview_optimized.log','preview_verification.log')]:copy(src,OUT/name)
for name in ['preview.png','preview.gif','detail.gif','levels.csv']:
    copy(MAT/name,OUT/'preview'/name)
shutil.copytree(ROOT/'proj/src/user_source',OUT/'source/proj/src/user_source')
for relative in ['proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al',
 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0.prj',
 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0.prj',
 'tools/build_phy.tcl','tools/build_spectrum_vectors.py','tools/package_spectrum_preview.py','tools/package_optimized_release.py',
 'sim/run_tests.ps1','sim/tb_album_navigation.v','sim/tb_spectrum_height.v','sim/tb_bmp_ack_cdc.v',
 'sim/tb_write_fifo_equivalence.v','sim/reference/frame_fifo_write_before_opt.v']:
    copy(ROOT/relative,OUT/'source'/relative)
hashes={p.relative_to(OUT/'source').as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((OUT/'source').rglob('*')) if p.is_file()}
(OUT/'source_sha256.json').write_text(json.dumps(hashes,indent=2,ensure_ascii=False),encoding='utf-8')
comparison=dict(baseline=old['resources'],optimized=resources,
   saved={k:old['resources'][k]-resources[k] for k in resources},
   baseline_domain_setup_ns=dict(video_clk=5.740,sd_card_clk=-.924,ext_mem_clk=-.860),optimized_domain_setup_ns=domains,
   baseline_setup_tns_ns=old['setup_tns_ns'],optimized_setup_tns_ns=stns,
   default_preview_307200_pixels_equal=True,all24frames_frequency_levels_and_peaks_equal=True)
(OUT/'comparison.json').write_text(json.dumps(comparison,indent=2),encoding='utf-8')
m=dict(built_on='2026-10-22',bitstream='oral_album_optimized.bit',bytes=len(data),sha256=digest,
       target='EG4S20BG256/HX4S20C',rtl_tests=58,resources=resources,setup_wns_ns=setup,setup_tns_ns=stns,
       hold_wns_ns=hold,hold_tns_ns=htns,domain_setup_wns_ns=domains,independent_review_complete=True,
       tf_modified=False,hardware_download_performed=False,hardware_test_pending=True)
(OUT/'manifest.json').write_text(json.dumps(m,indent=2,ensure_ascii=False),encoding='utf-8')
table='\n'.join(f"| {label} | {old['resources'][key]} | {resources[key]} | {old['resources'][key]-resources[key]} |"
                for label,key in [('LUT','lut'),('寄存器','register'),('DSP','dsp'),('BRAM9K','bram9k'),('PLL','pll')])
readme=f'''# 代码优化版：播放功能保持一致

下载：{OUT.as_posix()}/oral_album_optimized.bit

{len(data)}字节；SHA256：{digest.upper()}。

## 优化结果

| 资源 | 已确认的频谱版 | 本版 | 减少 |
| --- | --- | --- | --- |
{table}

视频同域Setup由+5.740ns变为{domains['video_clk']:+.3f}ns；SD卡同域由−0.924ns变为{domains['sd_card_clk']:+.3f}ns；存储同域由−0.860ns变为{domains['ext_mem_clk']:+.3f}ns。全局Hold {hold:+.3f}ns、HTNS0。减少了目录长路径、FIFO仲裁长算术和频谱高度计算资源，并补上图片读取应答的两级跨时钟同步。

58项RTL测试通过，含1048712组频谱高度精确比对、6种照片数量、ACK全部相位、FIFO逐拍等价。真实歌曲24帧的柱高/峰值轨迹和307200预览像素与已确认版本一致。完整独立复核通过。preview为生产RTL仿真，非实板录像。

厂商加密SDRAM控制器/硬核边界仍有全局Setup WNS {setup:.3f}ns、TNS {stns:.3f}ns；尚未宣称整体时序收敛。旧时钟分组及serializer关系的审计问题详见“实现与验证说明.md”，不以任意例外约束掩盖这些问题。优化版仍待你实板验收。

## TD下载步骤

1. TF继续用现有18张照片和歌曲，不需插电脑或改素材；连接电源、下载线、HDMI_B。
2. TD → Tools → BitWriter，器件EG4S20BG256，操作PROGRAM_SRAM，频率1 MHz。
3. Add File选择本目录oral_album_optimized.bit，选中该行后Run，等待PROGRAM_SRAM success。
4. 检查首图、音乐、逐字歌词和底边对齐频谱；手动连续切完18张并环回，检查第一张粒子转场及其他转场正常。
5. KEY4开启轮播，至少观察两个完整循环；检查画面无新增白边、断音或停滞。再用KEY4关闭轮播。
6. 正常短按KEY3应无暂停作用；长按约1秒进入/退出调节。模式内短按KEY3选择亮度/对比度，KEY2减、KEY4加；退出保留，KEY1整体复位恢复默认。

本轮未操作开发板、未写Flash；PROGRAM_SRAM断电后丢失。当前固定640×480帧长307200字，原写控制器的部分突发尾包限制保持，未新增不同分辨率支持。

## 回退

已确认正常的上一版：{PREV.as_posix()}/oral_album_spectrum_bars.bit

SHA256：{old['sha256'].upper()}。TF通用，下载方法相同。source为审阅快照；构建仍使用原工程路径。
'''
(OUT/'上板说明.md').write_text(readme,encoding='utf-8')
print(json.dumps(m,indent=2,ensure_ascii=False));print(json.dumps(comparison,indent=2));print(f'FROZEN {len(hashes)} source files: {OUT}')
