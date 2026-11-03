"""Freeze the reference-backed HDMI line marker fix and its measured evidence."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'release/20261023_hdmi_linefix'
PREV = ROOT / 'release/20261022_optimized'
MAT = ROOT / 'material/vendor_review_20261022'
RUNS = ROOT / 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY, SYN = RUNS / 'phy_1', RUNS / 'syn_1'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

old = json.loads((PREV / 'manifest.json').read_text(encoding='utf-8'))
assert sha(PREV / old['bitstream']) == old['sha256']
old_hashes = json.loads((PREV / 'source_sha256.json').read_text(encoding='utf-8'))
for rel, digest in old_hashes.items():
    assert sha(PREV / 'source' / rel) == digest, f'Frozen baseline changed: {rel}'
changed = [rel for rel, digest in old_hashes.items()
           if rel.startswith('proj/src/user_source/') and sha(ROOT / rel) != digest]
adapter = 'proj/src/user_source/hdl_source/video_rgb_to_axis_640x480.v'
assert changed == [adapter], changed
before = (PREV / 'source' / adapter).read_text(encoding='utf-8')
after = (ROOT / adapter).read_text(encoding='utf-8')
assert after == before.replace('// 一行首像素\n                S_x_cnt <= 11\'d0;',
                              '// 已接收首像素；第640个像素到达前计数为639。\n                S_x_cnt <= 11\'d1;')

regression = ROOT / 'sim/20261022_vendor_validation_regression.log'
assert 'ALL PASS: 59 RTL configurations' in regression.read_text(errors='replace')
summary_path = MAT / 'modelsim_validation/run_20261022_213856_qzo_4hvn/summary.json'
ms = json.loads(summary_path.read_text(encoding='utf-8'))
assert ms['success'] and ms['canary_rejected'] and len(ms['tests']) == 2
for test in ms['tests']:
    assert test['pass']
    for rel, digest in test['source_sha256'].items():
        assert sha(ROOT / rel) == digest, rel
probe = MAT / 'hdmi_encrypted/probe_result.txt'
assert 'PASS HDMI encrypted model' in probe.read_text() and 'FAIL' not in probe.read_text()
build = (PHY / 'build_vendor_validation.log').read_text(errors='replace')
assert 'finish command "bitgen' in build and 'BMP_ACK_META_COUNT: 1' in build
assert 'USR-8159' not in build and 'No pins matched' not in build
timing = (PHY / 'final_timing.rpt').read_text(errors='replace')
setup, stns = map(float, re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns', timing).groups())
hold, htns = map(float, re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns', timing).groups())
domains = {name: float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns',
           timing.split(f'Path Group     :     {name} -> {name}')[1]).group(1))
           for name in ['video_clk', 'sd_card_clk', 'ext_mem_clk']}
assert all(value > 0 for value in domains.values()) and hold >= 0 and htns == 0
assert setup == old['setup_wns_ns'] and stns == old['setup_tns_ns']
area = (PHY / 'HDMI1.4b_Transmitter_v1.0_phy.area').read_text()
resources = {key: int(re.search(r'^#'+tag+r'\s+(\d+)\s+out of', area, re.M).group(1))
             for key, tag in [('lut','lut'), ('register','reg'), ('bram9k','bram'), ('dsp','dsp'), ('pll','pll')]}
assert resources == old['resources']
bit = PHY / 'HDMI1.4b_Transmitter_v1.0.bit'
assert bit.stat().st_size == 670364
OUT.mkdir(exist_ok=False)

def copy(src, relative):
    dest = OUT / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)

copy(bit, 'oral_album_hdmi_linefix.bit')
for src, dest in [(regression,'regression.log'), (summary_path,'modelsim_summary.json'),
                  (probe,'hdmi_encrypted_probe.txt'), (PHY/'build_vendor_validation.log','build.log'),
                  (SYN/'synthesis_vendor_validation.log','synthesis.log'),
                  (PHY/'final_timing.rpt','final_timing.rpt'),
                  (PHY/'HDMI1.4b_Transmitter_v1.0_phy.area','resource.area'),
                  (PHY/'bmp_ack_internal.rpt','bmp_ack_internal.rpt'), (PHY/'route.qor','route.qor')]:
    copy(src, dest)
for relative in ['reference_audit/reference_findings.md','reference_audit/inventory.json',
                 'reference_audit/extraction_manifest.json', 'reference_audit/video_axis_formal_red.log',
                 'reference_audit/video_axis_formal_green.log', 'timing_audit/timing_review.md',
                 'timing_audit/simulation/controller_result.txt', 'modelsim_validation/README.md',
                 'modelsim_validation/test_runner_verdict.py', 'hdmi_encrypted/tb_hdmi_encrypted_probe.v',
                 'hdmi_encrypted/run.do','hdmi_encrypted/compile.log','hdmi_encrypted/eg4_compile.log',
                 'hdmi_encrypted/probe_load_eg4.log']:
    copy(MAT / relative, 'evidence/' + relative)
shutil.copytree(ROOT/'proj/src/user_source', OUT/'source/proj/src/user_source')
for rel in ['proj/src/td_project/HDMI1.4b_Transmitter_v1.0.al',
            'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/HDMI1.4b_Transmitter_v1.0.prj',
            'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1/HDMI1.4b_Transmitter_v1.0.prj',
            'tools/build_phy.tcl','tools/run_modelsim_validation.py','tools/package_hdmi_linefix_release.py',
            'sim/run_tests.ps1','sim/tb_video_rgb_to_axis_640x480.v','sim/tb_pcm_mix16.v']:
    copy(ROOT/rel, 'source/'+rel)
hashes = {p.relative_to(OUT/'source').as_posix(): sha(p)
          for p in sorted((OUT/'source').rglob('*')) if p.is_file()}
(OUT/'source_sha256.json').write_text(json.dumps(hashes, indent=2, ensure_ascii=False), encoding='utf-8')
manifest = dict(packaged_on='2026-10-23', built_on='2026-10-22', target='EG4S20BG256/HX4S20C',
                bitstream='oral_album_hdmi_linefix.bit', bytes=bit.stat().st_size, sha256=sha(bit),
                production_files_changed=changed, rtl_tests=59, modelsim_unit_tests=2,
                modelsim_failure_canary_rejected=True, encrypted_hdmi_tpg_smoke_cycles=1000,
                resources=resources, setup_wns_ns=setup, setup_tns_ns=stns,
                hold_wns_ns=hold, hold_tns_ns=htns, domain_setup_wns_ns=domains,
                full_system_timing_closed=False, sdram_external_model_experiment_pass=False,
                hardware_download_performed=False, hardware_test_pending=True, tf_modified=False)
(OUT/'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
readme = f'''# HDMI 行末标志修复版

位流：{OUT.as_posix()}/oral_album_hdmi_linefix.bit

大小 {manifest['bytes']} 字节；SHA256：{manifest['sha256'].upper()}。
构建于2026-10-22，整理交付于2026-10-23。

## 本版改动及验证

对照安路 APUG092 的接口约定，修复每行第640个像素遗漏TLAST的问题。仅一处生产RTL计数从0改为1，RGB、VALID、SOF延迟一致。旧版先复现失败；新版59组RTL回归通过，新增两帧逐像素检查包含614400个RGB像素、960次行末、2次帧首、消隐及中途复位。ModelSim-Altera Starter Edition 10.3c独立通过适配器和混音两个单元测试，故意失败检查被正确拒绝。

当前加密HDMI核及EG4原语库可在该ModelSim加载，内部TPG跑1000周期输出无X。这只是加密核兼容性冒烟测试，不代表已解码完整音视频、验证EDID或ACR。细节见同目录“资料与验证说明.md”。

资源LUT11563、寄存器6908、BRAM9K57、DSP14、PLL3。视频/SD卡/存储同域Setup分别+11.397/+0.134/+0.137ns，全局Hold+0.024ns。全局Setup仍为−6.699ns，TNS−294.431ns，均与上版相同；SDRAM硬IP边界尚未收敛，不能称全部优化完成。外部参考存储器模型的实验还发现数据关联失败，未据此改动生产控制器或时序约束。

## TD 下载步骤

1. TF使用当前18张照片和歌曲，无须更换素材；接好电源、下载线及HDMI_B。
2. 安路TD → Tools → BitWriter。器件选EG4S20BG256，操作选PROGRAM_SRAM，下载频率1 MHz。
3. Add File选择本目录oral_album_hdmi_linefix.bit，勾选该行，Run，等待PROGRAM_SRAM success。
4. 检查照片、歌曲、逐字歌词和底部频谱。KEY2连续切完18张并环回，第一张至第二张应为粒子转场；KEY4检查轮播至少两个完整循环。
5. 正常短按KEY3应无暂停作用。长按约1秒进入/退出调节，模式内短按KEY3选亮度/对比度，KEY2减、KEY4加；退出保留，KEY1复位。

本轮没有操作开发板或Flash，新版仍需实板验收。PROGRAM_SRAM断电丢失；固化不在本次操作内。

## 回退及复现

前一优化版：{PREV.as_posix()}/oral_album_optimized.bit

SHA256：{old['sha256'].upper()}。源码快照及哈希在source/与source_sha256.json。该快照用于审阅；完整回归素材和构建环境仍在原工程中。

在原工程目录执行 sim/run_tests.ps1 可跑59组回归；使用已安装Python执行 tools/run_modelsim_validation.py 可重跑两个ModelSim测试与失败检查，每次输出到新的隔离目录。ModelSim负责仿真；综合、布局布线及下载继续使用安路TD。
'''
(OUT/'上板说明.md').write_text(readme, encoding='utf-8')
print(json.dumps(manifest, ensure_ascii=False, indent=2))
print(f'FROZEN {len(hashes)} source files: {OUT}')
