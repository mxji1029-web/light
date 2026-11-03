"""Freeze measured aspect-fit/bilinear quality; never modify a card or board."""
from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'release/20261023_scale_quality'
RUNS=ROOT/'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY=RUNS/'phy_1'; SYN=RUNS/'syn_1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
baseline=ROOT/'release/20261023_all_extensions'
old=json.loads((baseline/'manifest.json').read_text(encoding='utf-8'))
assert sha(baseline/old['bitstream'])==old['sha256']
for rel,digest in json.loads((baseline/'source_sha256.json').read_text()).items():
 assert sha(baseline/'source'/rel)==digest,rel
reg=ROOT/'sim/20261023_scale_quality_signoff_regression.log'
assert 'ALL PASS: 79 RTL configurations' in reg.read_text(errors='replace')
MAT=ROOT/'material/scale_quality_20261023'
inputs=json.loads((MAT/'validation_source_sha256.json').read_text(encoding='utf-8'))
for rel,digest in inputs.items():assert sha(ROOT/rel)==digest,rel
parallel=json.loads((MAT/'parallel_signoff/summary.json').read_text(encoding='utf-8'))
assert parallel['success'] and parallel['serial_configurations']==70 and len(parallel['quality_cases'])==9
assert sha(ROOT/parallel['serial_log'])==parallel['serial_log_sha256']
for rel,digest in parallel['source_sha256'].items():assert sha(ROOT/rel)==digest,rel
glyph=ROOT/'sim/20261023_quality_glyph_final.log'
assert 'PASS: 8192 glyph rows' in glyph.read_text(errors='replace')
model_files=sorted((ROOT/'material/scale_quality_20261023/modelsim').glob('run_*/summary.json'),key=lambda p:p.stat().st_mtime)
model_path=model_files[-1]; model=json.loads(model_path.read_text(encoding='utf-8'))
assert model['success'] and model['canary_rejected'] and len(model['tests'])==4
for test in model['tests']:
 assert test['pass']
 for rel,digest in test['source_sha256'].items():assert sha(ROOT/rel)==digest,rel
log=(PHY/'build_scale_quality_final.log').read_text(errors='replace')
assert 'finish command "bitgen' in log and log.count('PLAYBACK_STAGE:')==4
assert 'USR-8159' not in log and 'No pins matched' not in log
timing=(PHY/'final_timing.rpt').read_text(errors='replace')
setup,stns=map(float,re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns',timing).groups())
hold,htns=map(float,re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns',timing).groups())
domains={name:float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns',timing.split(f'Path Group     :     {name} -> {name}')[1]).group(1)) for name in ['video_clk','sd_card_clk','ext_mem_clk']}
assert all(value>0 for value in domains.values()),domains
assert hold>=0 and htns==0
negative_groups={}
for section in re.split(r'Path Group\s*:\s*',timing)[1:]:
 name=section.splitlines()[0]
 match=re.search(r'Max\s*: SWNS\s+([-\d.]+)ns',section)
 if match and float(match[1])<0:negative_groups[name]=float(match[1])
assert set(negative_groups)=={'ext_mem_clk -> sys_pll_m0/pll_inst.clkc[2]','sys_pll_m0/pll_inst.clkc[2] -> ext_mem_clk'},negative_groups
area=(PHY/'HDMI1.4b_Transmitter_v1.0_phy.area').read_text()
resources={k:int(re.search(r'^#'+tag+r'\s+(\d+)\s+out of',area,re.M).group(1)) for k,tag in [('lut','lut'),('register','reg'),('bram9k','bram'),('dsp','dsp'),('pll','pll')]}
assert resources['bram9k']<=64 and resources['dsp']<=29 and resources['lut']<=19600
for name in ['pause_audio_internal.rpt','pause_sd_internal.rpt','bmp_ack_internal.rpt']:
 t=(PHY/name).read_text(errors='replace')
 assert re.search(r'Max\s*: SWNS\s+[\d.]+ns, STNS\s+0.000ns',t),name
 assert re.search(r'Min\s*: HWNS\s+[\d.]+ns, HTNS\s+0.000ns',t),name
bit=PHY/'HDMI1.4b_Transmitter_v1.0.bit'
bit_check=json.loads((MAT/'bitstream_check.json').read_text(encoding='utf-8'))
assert bit.stat().st_size==bit_check['bytes'] and sha(bit)==bit_check['sha256']
assert b'# Architecture: eagle_s20\n# Package: EG4S20BG256\n' in bit.read_bytes()[:256]
render=json.loads((MAT/'render/manifest.json').read_text(encoding='utf-8'))
for rel,digest in render['source_sha256'].items():assert sha(ROOT/rel)==digest,rel
metrics=json.loads((MAT/'audit/affine_rtl_metrics.json').read_text(encoding='utf-8'))
assert metrics['exact_q8_match'] and metrics['mse_reduction_percent']>90
for rel,digest in metrics['rtl_sha256'].items():assert sha(ROOT/rel)==digest,rel
assert 'PASS scale FIFO' in (MAT/'audit/fifo_pressure.log').read_text()
assert 'PASS all 16' in (MAT/'core/regression.log').read_text()
fit=json.loads((MAT/'fit/summary.json').read_text(encoding='utf-8'));assert len(fit)==16
fit_hashes=json.loads((MAT/'fit/final_source_hashes.json').read_text(encoding='utf-8'))
for rel,digest in fit_hashes['tested_sources_sha256'].items():assert sha(ROOT/rel)==digest,rel
pcm=json.loads((MAT/'pcm_timing/summary.json').read_text(encoding='utf-8'))
assert len(pcm['results'])==38
for rel,digest in pcm['sha256'].items():assert sha(ROOT/rel)==digest,rel
shared=json.loads((MAT/'shared_sd/summary.json').read_text(encoding='utf-8'))
assert shared['success'] and len(shared['cases'])==2
for rel,digest in shared['source_sha256'].items():assert sha(ROOT/rel)==digest,rel
assert (MAT/'final_review.md').exists()
for rel,digest in json.loads((MAT/'reviewer_check/review_source_sha256.json').read_text(encoding='utf-8')).items():assert sha(ROOT/rel)==digest,rel
OUT.mkdir(exist_ok=False)
def cp(src,rel):
 dest=OUT/rel; dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
cp(bit,'oral_album_scale_quality.bit')
for src,rel in [(reg,'regression.log'),(glyph,'glyph_verification.log'),(model_path,'modelsim_summary.json'),(PHY/'build_scale_quality_final.log','build.log'),(SYN/'synthesis_scale_quality_final.log','synthesis.log'),(PHY/'final_timing.rpt','final_timing.rpt'),(PHY/'HDMI1.4b_Transmitter_v1.0_phy.area','resource.area'),(PHY/'route.qor','route.qor')]:cp(src,rel)
for name in ['pause_audio_internal.rpt','pause_sd_internal.rpt','bmp_ack_internal.rpt']:cp(PHY/name,name)
shutil.copytree(ROOT/'proj/src/user_source',OUT/'source/proj/src/user_source')
for rel in ['proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al']+[f'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/{x}/HDMI1.4b_Transmitter_v1.0.prj' for x in ['syn_1','phy_1']]:cp(ROOT/rel,'source/'+rel)
for folder,suffixes in [('sim',{'.v','.ps1','.hex'}),('tools',{'.py','.ps1','.tcl','.cjs','.html'})]:
 for p in (ROOT/folder).rglob('*'):
  if p.is_file() and p.suffix in suffixes:cp(p,'source/'+p.relative_to(ROOT).as_posix())
for name in ['20261023_缩放画质深化.md','20261023_缩放画质复核.md']:
 p=ROOT/'docs'/name
 if p.exists():cp(p,name)
cp(MAT/'validation_source_sha256.json','validation_source_sha256.json')
cp(MAT/'bitstream_check.json','bitstream_check.json')
cp(MAT/'final_review.md','final_review.md')
cp(ROOT/parallel['serial_log'],'serial_regression_raw.log')
cp(ROOT/'sim/20261023_scale_quality_parallel_signoff.log','parallel_regression_driver.log')
for folder in ['render','audit','core','fit','pcm_timing','shared_sd','catalog_timing','reviewer_check','parallel_signoff']:
 for src in (MAT/folder).rglob('*'):
  if folder=='shared_sd':
   shared_parts=src.relative_to(MAT/folder).parts
   final_shared_dirs={Path(case['evidence_directory']).name for case in shared['cases']}
   if len(shared_parts)>1 and shared_parts[0] not in final_shared_dirs:continue
  if src.is_file() and src.suffix.lower() in {'.png','.json','.md','.py','.v','.sv','.log','.bmp','.do','.txt'} and not {'round1','before_tag_pipeline'}.intersection(src.parts):
   cp(src,'evidence/'+src.relative_to(MAT).as_posix())
hashes={p.relative_to(OUT/'source').as_posix():sha(p) for p in sorted((OUT/'source').rglob('*')) if p.is_file()}
(OUT/'source_sha256.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),encoding='utf-8')
m=dict(date='2026-10-23',bitstream='oral_album_scale_quality.bit',sha256=sha(bit),bytes=bit.stat().st_size,rtl_configurations=79,modelsim_tests=4,canary_rejected=True,core_cases=16,fit_cases=16,pcm_timing_cases=38,shared_sd_cases=2,resources=resources,domain_setup_ns=domains,negative_setup_groups=negative_groups,setup_wns_ns=setup,setup_tns_ns=stns,hold_wns_ns=hold,hold_tns_ns=htns,full_timing_closed=False,hardware_test_pending=True,tf_modified=False,board_programmed=False)
(OUT/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
note=f'''# 扩展03画质深化版

位流：{OUT.as_posix()}/oral_album_scale_quality.bit

SHA256：{m['sha256'].upper()}；{m['bytes']}字节。

## 本轮选择与改进

在五项扩展中集中深化03图片缩放：由横纵分别最近邻拉伸，升级为完整照片等比例居中、空余区域黑边、Q8双线性插值。横图/竖图保持原比例，放大边缘更平滑；1..1024源尺寸、24bit非压缩BMP、正负高度/行padding/大偏移继续支持。既有640×480图片权重为零，逐像素一致；不会自动给已经640×480的素材补出不存在的细节。

按align-origin坐标取四邻点、末行末列夹取、每轴Q8加128舍入；双行水平插值缓存复用源行，避免逐像素反复读卡。320×240案例连同图片头共452次sector请求，前版为1142；top-down或其他图的重读量不同。双线性不等于缩小抗混叠滤波，不保证所有棋盘/高频纹理都优于专用面积滤波。

实际RTL照片与竖图对照在evidence/render，图左为旧最近邻铺满、右为新等比双线性；均为仿真输出，不是板上截图。evidence/audit包含真实RTL渐变图：相对理想插值MSE由4.37639降到0.15204，下降96.53%，最大误差1 LSB。这是受控斜坡结论，不是任意照片画质评分。

## 下载与操作

1. 现有TF素材可继续使用。接好电源、下载线和HDMI_B。
2. TD → Tools → BitWriter，器件EG4S20BG256，PROGRAM_SRAM，频率1MHz。
3. Add File选本目录oral_album_scale_quality.bit，勾选并Run，等待PROGRAM_SRAM success。
4. 上电首图等待KEY3；短按释放开始/全部暂停/继续。KEY2手动切图、KEY4轮播、KEY3长按调节和菜单内短按选项均保留。
5. 连续切完18张并环回，检查第一张粒子、其余转场、歌词、频谱、参数OSD与音乐；轮播两完整循环并多次暂停恢复。
6. 当前TF中的640×480照片应保持原样。要看新增缩放差异，需要将小尺寸或非4:3照片安全部署至素材目录并更新LBA索引；本轮没有改写TF。evidence/render/family.bmp和portrait.bmp是本地测试输入，不能只复制后假定旧索引会自动引用。

## 验证、资源与限制

79组RTL配置通过，包含原70组及9组新默认画质模式全帧307200像素oracle；核心16例、包装16例、4项ModelSim与故意失败检查、综合字模位平面检查通过。两张图的新旧输出共1228800像素与独立数组模型逐一一致。

最终79组由完整70组串行回归及9个独立并行质量用例组成；中途串行驱动已完成的部分质量用例不重复计数。serial_regression_raw.log保留原日志，evidence/parallel_signoff保留每例独立编译/仿真日志、退出码和源哈希；regression.log为这两组结果的明确汇总。sim/run_tests.ps1仍可串行重现全部79组，未因并行调度改变生产RTL、TB断言或用例参数。

为拆开读卡域长路径，音频末样本判断提前注册，38个配置验证旧/新全部外部输出逐周期一致；目录头在字段完整后提前注册全32位合法性，进入目录状态后才以7位数量比较。没有修改音频采样率、卡时钟或时序例外。

真实BMP读取器+PCM读取器+原仲裁器的联合仿真：卡模型每32个100MHz周期一个字节，另加128周期命令延迟。320×240加载126.718ms、452图扇区；1024×1024加载1318.526ms、6721图扇区。两例音频字序核对通过，最低FIFO253字（容量512），最长音频请求等待15574周期/0.15574ms。该结论针对此卡模型，未替代实卡测试；保留2.684秒生产看门狗。

输出包含黑边也限速到最多每4个SD时钟1pixel。实际安路写FIFO+生产writer的有界压力测试：25M pixel/s、最多40mem周期读忙、307200字顺序正确，最大266/511占用；没有把此测试当作完整SDRAM/任意卡速的证明。

资源：{resources}。BRAM9K已64/64，后续加效果须重新分配存储。主要同域Setup(ns)：{domains}；全局Setup {setup:+.3f}ns/TNS {stns:.3f}ns，Hold {hold:+.3f}ns。普通同域仍为正，既有SDRAM硬IP边界问题未解决，未声称全局收敛。最大尺寸/慢卡与音乐共享仍需实板确认，外层加载看门狗约2.684秒。

本轮只改03相关加载链路，其他扩展/按键已回归；未操作开发板、TF或Flash。新bit仍待用户实板验收。旧版：{baseline.as_posix()}/{old['bitstream']}，SHA256 {old['sha256'].upper()}。

源码、工程配置与关键脚本快照在source/，哈希在source_sha256.json；完整构建和回归环境继续使用原工程。
'''
(OUT/'上板说明.md').write_text(note,encoding='utf-8')
files={p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()}
(OUT/'file_sha256.json').write_text(json.dumps(files,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(m,ensure_ascii=False,indent=2));print(f'FROZEN {len(hashes)} source files: {OUT}')
