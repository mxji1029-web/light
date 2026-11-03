"""Finish the nine independent quality cases after the frozen 70-case regression.

Keep original serial evidence, unique build directories, raw per-case results,
return codes and source hashes. No production or testbench source is changed.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'material/scale_quality_20261023/parallel_signoff'
SERIAL = ROOT / 'sim/20261023_scale_quality_signoff_serial.log'
COMBINED = ROOT / 'sim/20261023_scale_quality_signoff_regression.log'
HDL = ROOT / 'proj/src/user_source/hdl_source/SD'
CASES = [(320,240,0,54,0,0),(800,600,0,54,0,0),(321,241,1,1027,1,0),
         (640,480,0,54,0,0),(1024,1024,1,65535,0,1),(1,1,1,511,0,1),
         (17,13,1,499,1,1),(240,480,0,54,0,0),(1024,576,1,54,0,0)]
SOURCES = [ROOT/'sim/tb_bmp_scaling.v'] + [HDL/x for x in
    ['bmp_read.v','bmp_scale_stream.v','bmp_scale_quality.v','bmp_bilinear_stream.v']]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inputs():
    return {p.relative_to(ROOT).as_posix():sha(p) for p in SOURCES + [Path(__file__)]}

def run(case):
    sw,sh,top,offset,gaps,end = case
    name=f'{sw}x{sh}_t{top}_o{offset}_g{gaps}_e{end}'
    out=OUT/name
    out.mkdir(parents=True,exist_ok=False)
    executable=out/'case.vvp'
    params=dict(QUALITY=1,SW=sw,SH=sh,TOP_DOWN=top,OFFSET=offset,
                GAPPED=gaps,END_WITH_DATA=end)
    cmd=['D:/iverilog/bin/iverilog.exe','-g2012','-s','tb_bmp_scaling']
    cmd += [f'-Ptb_bmp_scaling.{k}={v}' for k,v in params.items()]
    cmd += ['-o',str(executable),*[str(p) for p in SOURCES]]
    started=time.monotonic()
    p=subprocess.run(cmd,capture_output=True,text=True,cwd=ROOT,timeout=120)
    (out/'compile.log').write_text(p.stdout+p.stderr,encoding='utf-8')
    if p.returncode:raise RuntimeError(f'{name}: compilation failed')
    p=subprocess.run(['D:/iverilog/bin/vvp.exe',str(executable)],
                     capture_output=True,text=True,cwd=ROOT,timeout=900)
    text=p.stdout+p.stderr
    (out/'simulate.log').write_text(text,encoding='utf-8')
    assert p.returncode==0 and 'pixels=307200' in text and 'PASS: BMP scale' in text,name
    assert not any(word in text for word in ['FATAL','FAIL:','ERROR:']),name
    result=dict(name=name,parameters=params,returncode=p.returncode,
                wall_seconds=time.monotonic()-started,
                pass_line=next(x for x in text.splitlines() if x.startswith('PASS: BMP scale')))
    print(result['pass_line'],flush=True)
    return result

def main():
    original=SERIAL.read_text(errors='replace')
    marker='ALL PASS: 70 RTL configurations; global transport, spectrum freeze, seven scaling cases and malformed headers included'
    assert marker in original and not any(x in original for x in ['FATAL','FAIL:'])
    serial_prefix=original[:original.index(marker)+len(marker)]+'\n'
    frozen=json.loads((ROOT/'material/scale_quality_20261023/validation_source_sha256.json').read_text(encoding='utf-8'))
    for rel,digest in frozen.items():assert sha(ROOT/rel)==digest,rel
    before=inputs()
    OUT.mkdir(exist_ok=False)
    results=[]
    with ThreadPoolExecutor(max_workers=4) as pool:
        for future in as_completed([pool.submit(run,c) for c in CASES]):
            results.append(future.result())
    assert before==inputs(),'Sources changed during quality signoff'
    for rel,digest in frozen.items():assert sha(ROOT/rel)==digest,rel
    summary=dict(success=True,serial_log=SERIAL.relative_to(ROOT).as_posix(),
                 serial_log_sha256=sha(SERIAL),serial_configurations=70,
                 source_sha256=before,quality_cases=results,
                 note='The original serial driver was stopped after its complete 70-case PASS; its partial quality work is not counted. All nine quality configurations ran independently here.')
    (OUT/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    combined=serial_prefix+'\nNine quality cases executed by run_quality_signoff_parallel.py; see per-case raw logs and summary.json.\n'
    combined+='\n'.join(r['pass_line'] for r in sorted(results,key=lambda x:x['name']))+'\n'
    combined+='ALL PASS: 79 RTL configurations; nine full-canvas bilinear/aspect-fit production cases included\n'
    COMBINED.write_text(combined,encoding='utf-8')
    print('PASS signoff: 70 serial configurations + 9 independent quality cases; frozen sources unchanged')

if __name__=='__main__':
    main()
