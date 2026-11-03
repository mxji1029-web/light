"""Live production HUD regression, using the independent frozen test/oracle suite."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
HERE=ROOT/'material/volume_status_20261025/hud'
RTL=ROOT/'proj/src/user_source/hdl_source'
sys.path.insert(0,str(HERE/'tests'))
from hud_oracle import check_all
p=argparse.ArgumentParser();p.add_argument('--name',required=True)
p.add_argument('--skip-raster',action='store_true',help='Explicit timer/CDC/events-only smoke; default checks all raster pixels')
a=p.parse_args();OUT=ROOT/'material'/a.name;OUT.mkdir(exist_ok=False)
inputs=[RTL/'playback_status_cdc.v',RTL/'playback_status_osd.v',*sorted((HERE/'tests').glob('*.*')),Path(__file__)]
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
before={str(f.relative_to(ROOT)):sha(f) for f in inputs if f.is_file()}
report={'runs':[],'raster_skipped':a.skip_raster,'input_sha256':before}
def native(name,top,modules,params=()):
    commands=[['D:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s',top,'-o',OUT/(name+'.vvp'),*params,HERE/'tests'/(top+'.v'),*[RTL/(m+'.v') for m in modules]],
              ['D:/iverilog/bin/vvp.exe',OUT/(name+'.vvp'),'+OUT='+OUT.as_posix()]]
    codes=[]
    for stage,cmd in zip(['compile','simulate'],commands):
        r=subprocess.run(list(map(str,cmd)),cwd=OUT,capture_output=True,timeout=300)
        (OUT/(name+'_'+stage+'.log')).write_bytes(r.stdout+r.stderr);codes.append(r.returncode)
        if r.returncode:raise RuntimeError((name,stage,r.returncode,(r.stdout+r.stderr).decode(errors='replace')[-900:]))
    report['runs'].append({'name':name,'native_exits':codes});print('PASS',name,flush=True)
if not a.skip_raster:
    native('raster','tb_hud_raster',['playback_status_osd'])
    report['oracle']=check_all(OUT);assert report['oracle']['mismatches']==0
native('default_timer','tb_hud_default_timer',['playback_status_osd'])
for sh,vh in [(7,5),(37,5),(3,11),(11,3)]:
    native(f'cdc_{sh}_{vh}','tb_status_cdc',['playback_status_cdc'],
           [f'-Ptb_status_cdc.SOURCE_HALF={sh}',f'-Ptb_status_cdc.VIDEO_HALF={vh}'])
native('independent_events','tb_hud_events',['playback_status_osd'])
assert before=={str(f.relative_to(ROOT)):sha(f) for f in inputs if f.is_file()},'Inputs changed during regression'
report['pass']=True;(OUT/'summary.json').write_text(json.dumps(report,indent=2))
print('PASS live HUD: timer, four CDC ratios, six independent events; raster '+('EXPLICITLY SKIPPED' if a.skip_raster else '3686400 pixels equal'))
