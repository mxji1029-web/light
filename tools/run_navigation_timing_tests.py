"""Recheck actual navigation, pause and SPI-stub integration after terminal retiming."""
from pathlib import Path
import argparse,subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[1];RTL=ROOT/'proj/src/user_source/hdl_source'
p=argparse.ArgumentParser();p.add_argument('--name',required=True);a=p.parse_args()
OUT=ROOT/'material/extension_deepening_20261024'/a.name;OUT.mkdir(exist_ok=False)
base=[RTL/'SD/sd_card_bmp.v',RTL/'pcm_sd_reader.v',RTL/'pcm_sd_arbiter.v']
cases=[('navigation_'+str(c),'tb_album_navigation',['-i',f'-Ptb_album_navigation.IMAGE_COUNT={c}'],base) for c in [1,2,3,18,22,63,64]]
cases += [(t,t,['-i'],base) for t in ['tb_album_pause','tb_commit_guard']]
cases += [('board_switch','tb_board_switch',['-DTB_FAKE_SD'],base+[ROOT/'sim/sd_card_stub.v',*[RTL/'SD'/f for f in ['bmp_read.v','bmp_scale_stream.v','bmp_scale_quality.v','bmp_bilinear_stream.v']],RTL/'photo_transition.v'])]
results={}
for name,top,params,sources in cases:
 test=[ROOT/'sim'/(top+'.v'),*sources]
 for stage,cmd in [('compile',['D:/iverilog/bin/iverilog.exe','-g2012',*params,'-s',top,'-o',OUT/(name+'.vvp'),*test]),('run',['D:/iverilog/bin/vvp.exe',OUT/(name+'.vvp')])]:
  r=subprocess.run(list(map(str,cmd)),cwd=OUT,capture_output=True,timeout=900)
  (OUT/(name+'_'+stage+'.log')).write_bytes(r.stdout+r.stderr)
  print(name,stage,r.returncode,(r.stdout+r.stderr).decode(errors='replace')[-700:],flush=True)
  assert r.returncode==0,(name,stage)
 results[name]={'pass':True,'source_sha256':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in test}}
(OUT/'summary.json').write_text(json.dumps({'pass':True,'results':results},indent=2))
