"""Validate frozen 81-case/TD evidence, then create a new release. --check is read-only."""
from pathlib import Path
import argparse, hashlib, json, re, shutil

ROOT = Path(__file__).resolve().parents[1]
MAT = ROOT / 'material/spectrum_quality_20261023'
OUT = ROOT / 'release/20261023_spectrum32_quality'
RUNS = ROOT / 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs'
PHY, SYN = RUNS / 'phy_1', RUNS / 'syn_1'
BASE = ROOT / 'release/20261023_scale_quality'
BITNAME = 'oral_album_spectrum32_quality.bit'
QUALITY_SHA = 'b8525cc734602a9b82270e49280583d6b96ae6bdd3ea2a2ce9310550d06e84d6'
OLD_SHA = 'd0b7199d25e7c717293b8a8fba797be494dd33e34577f40d4d71e31b4db08dc7'

def require(condition, message):
    if not condition: raise RuntimeError(message)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return path.read_text(encoding='utf-8-sig', errors='replace')
def js(path): return json.loads(read(path))
def verify(mapping, base=ROOT):
    require(bool(mapping), 'Empty hash manifest')
    for rel, digest in mapping.items():
        path = (base / rel).resolve()
        require(path.is_relative_to(base.resolve()), f'Hash path escapes root: {rel}')
        require(path.is_file() and sha(path) == digest.lower(), f'Hash mismatch/missing: {path}')

def latest_run(directory):
    paths = sorted(p for p in directory.glob('run_*') if p.is_dir())
    require(bool(paths), f'No run directory: {directory}')
    return paths[-1]  # Never fall back to an older completed run.

def validate():
    old = js(BASE / 'manifest.json')
    require(old['sha256'] == OLD_SHA and sha(BASE / old['bitstream']) == OLD_SHA, 'Rollback bit changed')
    verify(js(BASE / 'source_sha256.json'), BASE / 'source')
    frozen = js(MAT / 'review/final_source_manifest.json')
    producer = frozen['source_sha256']; verify(producer)
    require(sha(ROOT / 'proj/src/user_source/hdl_source/audio_spectrum_quality.v') == QUALITY_SHA, 'Renderer is not frozen streaming RTL')
    require(frozen['frozen_quality_sha256'] == QUALITY_SHA, 'Review freeze uses different renderer')
    require(read(MAT / 'final_review.md').strip(), 'Final independent review missing')
    sdc = 'proj/src/user_source/constraints_source/timing.sdc'
    require(sha(ROOT / sdc) == sha(BASE / 'source' / sdc), 'SDC changed from accepted rollback')

    model_path = latest_run(MAT / 'modelsim_stream') / 'summary.json'; model = js(model_path)
    names = {'tb_pcm_mix16', 'tb_video_rgb_to_axis_640x480', 'tb_picture_controls', 'tb_bmp_scaling', 'tb_spectrum_quality_display'}
    require(model['success'] and model['canary_rejected'] and {x['name'] for x in model['tests']} == names and len(model['tests']) == 5, 'Five fresh ModelSim tests/canary required')
    for test in model['tests']:
        require(test['pass'] and 'PASS' in test['result'] and all(s['returncode'] == 0 for s in test['steps']), 'ModelSim case failed')
        verify(test['source_sha256'])
    require(not model['canary']['pass'] and 'FAIL:' in model['canary']['result'], 'ModelSim canary did not execute/reject')
    ram = js(MAT / 'ram32/modelsim_summary.json')
    require(not ram['success'] and not ram['primitive']['pass'] and ram['primitive']['stage'] == 'simulate', 'Reassess actual RAM primitive validation status')
    require(any(s['step'] == 'simulate' and s['returncode'] == 12 for s in ram['primitive']['steps']), 'RAM primitive load failure evidence missing')
    require(ram['rtl_sha256'] == sha(ROOT / 'proj/src/user_source/hdl_source/spectrum_complex_ram.v'), 'RAM primitive evidence source drifted')
    require(all(x['returncode'] == 0 for x in js(MAT / 'ram32/iverilog_summary.json')), 'Behavioral RAM failed')
    require('PASS' in read(MAT / 'ram32/iverilog_run.log'), 'Behavioral RAM marker missing')

    original = js(MAT / 'audit/rtl_music_source_manifest.json')
    for item in original:
        if Path(item['path']).name in {'spectrum_fft1024.v', 'spectrum_complex_ram.v'}:
            require(sha(ROOT / item['path']) == item['sha256'], 'Original music FFT/RAM changed')
    original_quality = ROOT / 'backups/20261023_before_spectrum_quality/audio_spectrum_quality_prepack.v'
    old_quality_sha = next(x['sha256'] for x in original if Path(x['path']).name == 'audio_spectrum_quality.v')
    require(sha(original_quality) == old_quality_sha, 'Original trajectory RTL snapshot changed')
    require(original_quality.read_bytes().split(b'module audio_spectrum_display32(')[0] == (ROOT / 'proj/src/user_source/hdl_source/audio_spectrum_quality.v').read_bytes().split(b'module audio_spectrum_display32(')[0], 'Original frontend changed beyond renderer optimization')
    # Old renderer hash is deliberately retained: new streaming renderer has a separate differential proof.
    replay_dir = MAT / 'audit/renderer_streaming_replay'; replay = js(replay_dir / 'replay_manifest.json')
    for item in replay['sources']: require(sha(ROOT / item['path']) == item['sha256'], 'Streaming replay source/golden changed')
    diff = js(replay_dir / 'differential_results.json')
    require(diff['publishes'] == 140 and diff['video_frames'] == 179 and diff['overrun'] == 0 and diff['result'].startswith('PASS'), 'Streaming differential failed')
    require(diff['original_trace_sha256'] == sha(MAT / 'audit/music_trace.txt') and diff['optimized_trace_sha256'] == sha(replay_dir / 'optimized_renderer_trace.txt'), 'Differential log changed')
    trajectory = js(MAT / 'audit/rtl_music_trace_results.json')
    require(trajectory['FFT_bin_values_checked'] == 71680 and trajectory['FFT_mismatch_count'] == trajectory['overrun'] == 0, 'Original full-chain trajectory failed')
    require('PASS' in read(MAT / 'review/stream_bands.log') and 'PASS' in read(MAT / 'review/frontend_boundaries.log'), 'Independent streaming/frontend review failed')

    build_path = PHY / 'build_spectrum_quality_stream.log'; build = read(build_path)
    synthesis = SYN / 'synthesis_spectrum_quality_stream.log'
    require(len(re.findall(r'finish command "bitgen\b', build)) == 1 and build.count('PLAYBACK_STAGE:') == 4, 'Fresh TD bitgen/pause markers missing')
    require(re.search(r'BMP_ACK[^\n]*COUNT:\s*1\b', build), 'BMP ACK collection marker missing')
    require('USR-8159' not in build and 'No pins matched' not in build and 'Failed in Packing' not in build, 'TD build error')
    require('finish command "optimize_gate' in read(synthesis), 'Final synthesis did not finish')
    bit = PHY / 'HDMI1.4b_Transmitter_v1.0.bit'; header = bit.read_bytes()[:256]
    require(b'# Architecture: eagle_s20\n# Package: EG4S20BG256\n' in header, 'Wrong bit architecture/package')
    require(bit.stat().st_mtime >= synthesis.stat().st_mtime and bit.stat().st_mtime <= build_path.stat().st_mtime + 2, 'Stale bit mtime')
    require(all(bit.stat().st_mtime >= (ROOT / p).stat().st_mtime for p in producer), 'Bit predates frozen producer input')
    if 'bitstream' in frozen:
        require(sha(bit) == frozen['bitstream']['sha256'] and bit.stat().st_size == frozen['bitstream']['size'], 'Bit differs from reviewed build')
    timing_path = PHY / 'final_timing.rpt'; timing = read(timing_path)
    setup, stns = map(float, re.search(r'SWNS:\s*([-\d.]+)ns, STNS:\s*([-\d.]+)ns', timing).groups())
    hold, htns = map(float, re.search(r'HWNS:\s*([-\d.]+)ns, HTNS:\s*([-\d.]+)ns', timing).groups())
    negative = {}
    for section in re.split(r'Path Group\s*:\s*', timing)[1:]:
        value = re.search(r'Max\s*: SWNS\s+([-\d.]+)ns', section)
        if value and float(value[1]) < 0: negative[section.splitlines()[0].strip()] = float(value[1])
    require(set(negative) == {'ext_mem_clk -> sys_pll_m0/pll_inst.clkc[2]', 'sys_pll_m0/pll_inst.clkc[2] -> ext_mem_clk'}, 'Unexpected negative timing group')
    require((setup, stns, hold, htns) == (-6.699, -297.791, .027, 0.), 'Final stream timing differs from reviewed result')
    area_path = PHY / 'HDMI1.4b_Transmitter_v1.0_phy.area'; area = read(area_path)
    resources = {name: int(re.search(r'^#' + tag + r'\s+(\d+)\s+out of', area, re.M)[1]) for name, tag in [('lut','lut'),('register','reg'),('bram9k','bram'),('bram32k','bram32k'),('dsp','dsp'),('pll','pll')]}
    require(resources == dict(lut=16558, register=8473, bram9k=64, bram32k=4, dsp=23, pll=3), 'Final resource fingerprint differs')
    require('Confidence          : Routed' in timing, 'Final timing report is not routed')
    domains = {name: float(re.search(r'Max\s*: SWNS\s+([-\d.]+)ns', timing.split(f'Path Group     :     {name} -> {name}')[1])[1]) for name in ['video_clk','sd_card_clk','ext_mem_clk']}
    require(all(value > 0 for value in domains.values()), 'Unexpected intra-domain setup failure')
    require(min(timing_path.stat().st_mtime, area_path.stat().st_mtime) >= synthesis.stat().st_mtime, 'Stale timing/resource report')
    glyph_path = ROOT / 'sim/20261023_spectrum_quality_glyph.log'
    require('PASS: 8192 glyph rows x 31 stored bit planes match bit for bit' in read(glyph_path), 'Synthesized glyph verification missing')
    require((SYN / 'lyric_gate_inspection.v').stat().st_mtime >= synthesis.stat().st_mtime, 'Stale inspected glyph netlist')
    regression = latest_run(MAT / 'regression')
    require((regression / 'results81.json').is_file(), 'Fresh81 final results81.json missing: regression incomplete')
    r = js(regression / 'results81.json')
    require(r['success'] and r['sources_unchanged'] and r['configurations'] == 81, 'Fresh81 incomplete/failed')
    require(r['serial_configurations'] == 72 and r['parallel_quality_configurations'] == 9, 'Fresh81 case counts differ')
    require(len(r['results']) == 81 and len({x['name'] for x in r['results']}) == 81, '81 unique results required')
    verify(r['source_sha256']); verify(r['evidence_sha256'], regression)
    before, after = js(regression / 'source_before.json'), js(regression / 'source_after.json')
    require(before == after == r['source_sha256'], 'Regression sources drifted'); verify(before)
    for case in r['results']:
        require(case['pass'] and case['compile_returncode'] == case['simulate_returncode'] == 0, f'Failed case {case["name"]}')
        for stage in ['compile', 'simulate']:
            path = Path(case[stage + '_log'])
            if not path.is_absolute(): path = regression / path
            require(path.is_file() and sha(path) == case[stage + '_log_sha256'], f'Case log changed: {path}')
        require('PASS' in read(path) and not re.search(r'FATAL|FAIL:|ERROR:', read(path)), f'No clean runtime PASS: {path}')
    require('ALL PASS: 81 RTL configurations' in read(regression / 'regression.log'), 'Fresh81 final marker missing')
    return locals()

def package(v):
    require(not OUT.exists(), f'Release already exists: {OUT}')
    OUT.mkdir(parents=True, exist_ok=False)
    evidence = {}
    frozen_inputs = {**v['before'], **v['producer']}
    frozen_inputs[v['bit'].relative_to(ROOT).as_posix()] = v['frozen']['bitstream']['sha256']
    def copy(path, rel):
        digest = sha(path)
        expected = frozen_inputs.get(path.relative_to(ROOT).as_posix())
        if expected: require(digest == expected, f'Input changed after validation: {path}')
        dest = OUT / rel; dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest); require(sha(dest) == digest == sha(path), f'Copy drift: {path}')
        evidence[path.relative_to(ROOT).as_posix()] = digest
    copy(v['bit'], BITNAME)
    for path, rel in [(v['build_path'],'build.log'), (v['synthesis'],'synthesis.log'), (v['timing_path'],'final_timing.rpt'), (v['area_path'],'resource.area'), (v['model_path'],'modelsim_summary.json')]: copy(path, rel)
    copy(v['glyph_path'], 'glyph_verification.log')
    for rel in v['producer']: copy(ROOT / rel, 'source/' + rel)
    for folder, suffixes in [('sim',{'.v','.sv','.vh','.ps1','.hex'}), ('tools',{'.py','.ps1','.tcl','.cjs','.html'})]:
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and path.suffix.lower() in suffixes and '__pycache__' not in path.parts: copy(path, 'source/' + path.relative_to(ROOT).as_posix())
    suffixes = {'.json','.jsonl','.md','.py','.ps1','.tcl','.v','.sv','.vh','.do','.log','.rpt','.area','.qor','.txt','.png','.gif','.html','.wav'}
    excluded = {'work','eg4','binaries','__pycache__','modelsim_lib','vendor','sources'}
    raw = {'music_bins.txt','music_trace.txt','optimized_renderer_trace.txt','stimulus.txt','outputs.txt'}
    gifs = {'32bar_fixed_fft_8s.gif','rtl_3s_trace_synthetic.gif'}
    selected_runs = {v['regression'].name, v['model_path'].parent.name}
    for folder in ['review','audit','fft','ram32','display','integration','modelsim_stream','regression']:
        for path in sorted((MAT / folder).rglob('*')):
            if not path.is_file() or path.suffix.lower() not in suffixes: continue
            parts = path.relative_to(MAT).parts
            if excluded.intersection(parts) or path.name in raw or path.name.startswith('eg_phy_'): continue
            if any(p.startswith('run_') and p not in selected_runs for p in parts[:-1]): continue
            if path.stat().st_size > 2_000_000 or (path.suffix == '.gif' and path.name not in gifs): continue
            if path.suffix == '.wav' and path.name != 'actual_music_58_66s.wav': continue
            copy(path, 'evidence/' + path.relative_to(MAT).as_posix())
    copy(MAT / 'final_review.md', 'final_review.md')
    copy(v['original_quality'], 'evidence/audit/original_trajectory_quality.v')
    copy(ROOT / 'docs/20261023_32频带频谱深化.md', '20261023_32频带频谱深化.md')
    for rel in ['docs/superpowers/specs/2026-10-23-spectrum-quality-design.md']:
        copy(ROOT / rel, rel)
    verify(v['producer']); verify(v['before'])
    verify(v['producer'], OUT / 'source')
    def write(name, data): (OUT / name).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    write('build_input_sha256.json', v['producer'])
    write('validation_source_sha256.json', v['before'])
    write('evidence_sha256.json', evidence)
    write('bitstream_check.json', dict(sha256=sha(v['bit']),bytes=v['bit'].stat().st_size,mtime=v['bit'].stat().st_mtime,architecture='eagle_s20',package='EG4S20BG256',fresh_bitgen_marker=True))
    source = {p.relative_to(OUT/'source').as_posix():sha(p) for p in sorted((OUT/'source').rglob('*')) if p.is_file()}
    write('source_sha256.json', source)
    manifest = dict(date='2026-10-23',bitstream=BITNAME,sha256=sha(v['bit']),bytes=v['bit'].stat().st_size,rtl_configurations=81,modelsim_tests=5,canary_rejected=True,
        resources=v['resources'],domain_setup_ns=v['domains'],setup_wns_ns=v['setup'],setup_tns_ns=v['stns'],hold_wns_ns=v['hold'],hold_tns_ns=v['htns'],negative_setup_groups=v['negative'],
        ram_behavioral_pass=True,ram_vendor_model_pass=False,ram_vendor_model_stage='load exited12; TB did not execute',
        full_timing_closed=False,hardware_test_pending=True,tf_modified=False,board_programmed=False,rollback_bitstream=str(BASE/v['old']['bitstream']),rollback_sha256=OLD_SHA,
        regression_resumed=True,regression_preserved_configurations=46,serial_configurations=72,parallel_quality_configurations=9,
        validation='Original full-chain3s + frozen optimized renderer exact replay; not another full-chain75M run')
    write('manifest.json', manifest)
    note = f'''# 32根暖金细柱频谱深化版

位流：{BITNAME}，{manifest['bytes']}字节；SHA256：{manifest['sha256'].upper()}。

1024点Hann FFT覆盖bin1..512，32个连续频带；36.12dB显示窗、有限自动显示增益、真实静音门和定点底扣除，统一底边、39px柱高及峰值线。仅改变显示，不改变音频声流、照片画质/转场、歌词、按键语义或TF素材。

## 用户下载

1. 现有TF卡插回开发板，接好电源、USB下载线及HDMI_B。
2. 打开安路TD，进入Tools → BitWriter。
3. 选择下载器，扫描器件并确认EG4S20BG256，操作模式选PROGRAM_SRAM，下载频率1MHz。
4. Add File选择本目录{BITNAME}，勾选该文件，点击Run。
5. 等待PROGRAM_SRAM success，首张照片出现后短按释放KEY3开始播放。
6. 本次为SRAM下载，上电自动运行的Flash固化需另做。本轮未替用户下载、未写Flash或改TF。

现有TF可直接继续使用。KEY3短按释放开始/全部暂停/继续；KEY2切图、KEY4轮播、KEY3长按参数菜单保持原行为。检查32根细柱随实际音乐起落、底边稳定、歌词/照片无越界，重复暂停恢复并轮播两轮。真实高频为空时末几根柱允许不动，不用随机数补运动。

## 证据与限制

81项fresh RTL配置、5项ModelSim及故意失败canary通过。原全链真实3秒验证71680频点与179视频帧；资源优化后的冻结renderer另以同一原始频点/VS做精确差分，140次发布时刻及全部柱/峰值/参考一致，不宣称新冻结RTL又跑了完整75Mclk。8秒HTML/WAV/GIF为个人曲目片段的数值模型试听；RTL轨迹图由寄存器值在PC合成，均非开发板HDMI截图。完整歌曲未复制。

全套回归保留中断前46项完整通过记录；确认源码哈希未变后，重编译中断的Height用例并续跑其余26项串行和9项并行配置，共81项。未引用旧发布结果，未计入中断且未完成的仿真；interrupted_regression_raw.log、continuation.log、resume_metadata.json和每项原始日志均保留。

BRAM32K行为测试和TD原语映射通过；官方受保护RAM原语在旧ModelSim10.3c加载退出12，TB未执行，该层未通过，不能被5项普通RTL测试掩盖。未复制安装目录的vendor库/受保护源码/编译work数据库。

资源：{v['resources']}。普通同域Setup(ns)：{v['domains']}。全局Setup -6.699ns/TNS -297.791ns，Hold +0.027ns；仍是既有两组SDRAM硬IP边界负Setup，SDC未改，不声称全局时序收敛。最初Packing4994>4900失败及后续修复证据保留，最终日志完成bitgen。新bit仍需用户实板验收。

回退：{(BASE/v['old']['bitstream']).as_posix()}；SHA256：{OLD_SHA.upper()}。

源码/工程在source/；source_sha256.json、build_input_sha256.json、validation_source_sha256.json、evidence_sha256.json和file_sha256.json分别记录源码、构建输入、验证输入、证据来源和包内文件哈希。包内哈希清单不自包含其自身。
'''
    (OUT/'上板说明.md').write_text(note,encoding='utf-8')
    write('file_sha256.json', {p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()})
    print(json.dumps(manifest,ensure_ascii=False,indent=2)); print('FROZEN', OUT)

def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    state=validate()
    if args.check: print('PASS all frozen release preconditions; no files copied')
    else: package(state)

if __name__ == '__main__': main()
