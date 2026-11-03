"""Freeze measured playback/scaling features; never modify a card or board."""
from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'release/20261023_all_extensions'
RUNS=ROOT/'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY=RUNS/'phy_1'; SYN=RUNS/'syn_1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
baseline=ROOT/'release/20261023_hdmi_linefix'
old=json.loads((baseline/'manifest.json').read_text(encoding='utf-8'))
assert sha(baseline/old['bitstream'])==old['sha256']
for rel,digest in json.loads((baseline/'source_sha256.json').read_text()).items():
 assert sha(baseline/'source'/rel)==digest,rel
reg=ROOT/'sim/20261023_extensions_release_regression.log'
assert 'ALL PASS: 70 RTL configurations' in reg.read_text(errors='replace')
glyph=ROOT/'sim/20261023_glyph_verification.log'
assert 'PASS: 8192 glyph rows' in glyph.read_text(errors='replace')
model_files=sorted((ROOT/'material/all_extensions_modelsim_20261023').glob('run_*/summary.json'),key=lambda p:p.stat().st_mtime)
model_path=model_files[-1]; model=json.loads(model_path.read_text(encoding='utf-8'))
assert model['success'] and model['canary_rejected'] and len(model['tests'])==4
for test in model['tests']:
 assert test['pass']
 for rel,digest in test['source_sha256'].items():assert sha(ROOT/rel)==digest,rel
log=(PHY/'build_extensions_release.log').read_text(errors='replace')
assert 'finish command "bitgen' in log and log.count('PLAYBACK_STAGE:')==4
assert 'USR-8159' not in log and 'No pins matched' not in log
timing=(PHY/'final_timing.rpt').read_text(errors='replace')
setup,stns=map(float,re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns',timing).groups())
hold,htns=map(float,re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns',timing).groups())
domains={name:float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns',timing.split(f'Path Group     :     {name} -> {name}')[1]).group(1)) for name in ['video_clk','sd_card_clk','ext_mem_clk']}
assert all(value>0 for value in domains.values()),domains
assert hold>=0 and htns==0
area=(PHY/'HDMI1.4b_Transmitter_v1.0_phy.area').read_text()
resources={k:int(re.search(r'^#'+tag+r'\s+(\d+)\s+out of',area,re.M).group(1)) for k,tag in [('lut','lut'),('register','reg'),('bram9k','bram'),('dsp','dsp'),('pll','pll')]}
assert resources['bram9k']<=64 and resources['dsp']<=29 and resources['lut']<=19600
for name in ['pause_audio_internal.rpt','pause_sd_internal.rpt','bmp_ack_internal.rpt']:
 t=(PHY/name).read_text(errors='replace')
 assert re.search(r'Max\s*: SWNS\s+[\d.]+ns, STNS\s+0.000ns',t),name
 assert re.search(r'Min\s*: HWNS\s+[\d.]+ns, HTNS\s+0.000ns',t),name
bit=PHY/'HDMI1.4b_Transmitter_v1.0.bit'; assert bit.stat().st_size==670364
OUT.mkdir(exist_ok=False)
def cp(src,rel):
 dest=OUT/rel; dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
cp(bit,'oral_album_all_extensions.bit')
for src,rel in [(reg,'regression.log'),(glyph,'glyph_verification.log'),(model_path,'modelsim_summary.json'),(PHY/'build_extensions_release.log','build.log'),(SYN/'synthesis_extensions_release.log','synthesis.log'),(PHY/'final_timing.rpt','final_timing.rpt'),(PHY/'HDMI1.4b_Transmitter_v1.0_phy.area','resource.area'),(PHY/'route.qor','route.qor')]:cp(src,rel)
for name in ['pause_audio_internal.rpt','pause_sd_internal.rpt','bmp_ack_internal.rpt']:cp(PHY/name,name)
shutil.copytree(ROOT/'proj/src/user_source',OUT/'source/proj/src/user_source')
for rel in ['proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al']+[f'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/{x}/HDMI1.4b_Transmitter_v1.0.prj' for x in ['syn_1','phy_1']]:cp(ROOT/rel,'source/'+rel)
for folder,suffixes in [('sim',{'.v','.ps1','.hex'}),('tools',{'.py','.ps1','.tcl','.cjs','.html'})]:
 for p in (ROOT/folder).rglob('*'):
  if p.is_file() and p.suffix in suffixes:cp(p,'source/'+p.relative_to(ROOT).as_posix())
for name in ['20261023_FPGA图片缩放说明.md','20261023_扩展项开源调研.md','20261023_扩展实现复核.md','20261023_全局播放与五项扩展.md']:
 p=ROOT/'docs'/name
 if p.exists():cp(p,name)
shutil.copytree(ROOT/'material/scaling_demo_20261023',OUT/'缩放演示素材')
shutil.copytree(ROOT/'material/extension_research_20261023',OUT/'开源调研证据')
hashes={p.relative_to(OUT/'source').as_posix():sha(p) for p in sorted((OUT/'source').rglob('*')) if p.is_file()}
(OUT/'source_sha256.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),encoding='utf-8')
m=dict(date='2026-10-23',bitstream='oral_album_all_extensions.bit',sha256=sha(bit),bytes=bit.stat().st_size,rtl_configurations=70,modelsim_tests=4,canary_rejected=True,resources=resources,domain_setup_ns=domains,setup_wns_ns=setup,setup_tns_ns=stns,hold_wns_ns=hold,hold_tns_ns=htns,full_timing_closed=False,hardware_test_pending=True,tf_modified=False,board_programmed=False)
(OUT/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
note=f'''# 五项扩展与全局播放控制版

位流：{OUT.as_posix()}/oral_album_all_extensions.bit

SHA256：{m['sha256'].upper()}；{m['bytes']}字节。

## 按键

上电自动加载首张照片，音乐和轮播进度等待KEY3短按。正常模式短按KEY3并松开：开始→全部暂停→继续。暂停冻结音乐位置、逐字歌词、转场进度、频谱柱条及轮播剩余计时；HDMI持续显示，音频送静音，正在读卡/写帧的事务安全结束。

KEY2手动切图请求保留；暂停时请求可加载下一张，转场停在当前进度，继续播放后完成。KEY4切换轮播模式；暂停时不启动轮播计时。长按KEY3约1秒进入/退出调节，菜单内短按KEY3仍选亮度/对比度，KEY2减、KEY4加。复位恢复默认且回到暂停。数码管音频状态1为播放、2为暂停。

## 五项扩展

| 项目 | 本版能力 |
| --- | --- |
| 01 图层与字幕 | 原逐字中文书法歌词、音量跳动、按音频位置换句；暂停后冻结 |
| 02 转场 | 第1→2张粒子及既有12种遮罩转场；暂停保留进度 |
| 03 缩放适配 | FPGA自主解析源BMP，最近邻生成640×480，无需电脑预缩放 |
| 04 实时调节 | 保留亮度−64..64及5档对比度、中文OSD参数 |
| 05 音频可视化 | 保留真实16频点Goertzel，柱底对齐、缓降与峰帽，暂停冻结 |

缩放输入：宽高各1..1024，24bit非压缩BI_RGB，DIB40/108/124，planes=1，像素偏移不超过65535；支持正/负高度、行补齐和RGB跨扇区。按floor坐标取样，固定拉伸至640×480，未实现保持比例加黑边或双线性。仅增加512字节扇区缓存，横向重复像素复用RGB。声明像素区长度不足等非法头拒绝，读卡超时/物理坏卡仍需外层重试。实际加载时间取决于尺寸、重复行读卡与SD速率。

## 下载及验收

1. 当前TF素材继续使用；接好电源、下载器、HDMI_B。
2. TD → Tools → BitWriter，EG4S20BG256，PROGRAM_SRAM，1MHz。
3. Add File选择本目录oral_album_all_extensions.bit，勾选并Run，等待PROGRAM_SRAM success。
4. 上电应显示首张、无音乐。短按KEY3开始，播放中再次短按检查歌词/音乐/频谱/转场暂停；再次按下应从原进度连续恢复。
5. 检查KEY2、KEY4及长按调节功能；轮播至少两个18张循环，检查粒子转场、其余样式和首尾环回。
6. “缩放演示素材”含320×240、800×600及321×241负高度BMP与参考PNG，尚未写入TF目录。当前18张640×480素材验证兼容性；非640实板缩放演示需要另行安全更新素材目录/LBA索引，不能仅复制BMP后假定现有索引会自动引用。

## 验证与边界

70组RTL配置通过，包括7种缩放配置逐个检查307200像素、12种坏头、完整公开顶层暂停链路、真实I2S频谱冻结；ModelSim4个单元及故意失败检查通过。新同步器首级单独处理，级间路径仍有正常时序报告。公开顶层仿真省略了PLL/存储器/加密HDMI边界，不是完整板级电气仿真。

TD综合/布局布线/位流生成完成。资源：{resources}。主要同域Setup(ns)：{domains}；全局Setup {setup:+.3f}ns，TNS {stns:.3f}ns；Hold {hold:+.3f}ns。厂商SDRAM边界既有问题仍在，未声称整体时序收敛。所有实板功能仍待用户下载验收，本轮未写TF、SRAM或Flash。

本轮实查GitHub Video Stream Scaler、Project F、ZipCPU FFT的固定提交及许可，取舍见开源调研；本轮缩放为项目自编实现，没有直接集成这三个内核。已有转场来源另见工程third_party记录。

回退：{baseline.as_posix()}/{old['bitstream']}。保留原TF目录即可兼容。源快照和哈希便于核对，完整工具环境仍使用原工程。
'''
(OUT/'上板说明.md').write_text(note,encoding='utf-8')
files={p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()}
(OUT/'file_sha256.json').write_text(json.dumps(files,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(m,ensure_ascii=False,indent=2));print(f'FROZEN {len(hashes)} source files: {OUT}')
