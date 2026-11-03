from pathlib import Path
import argparse,subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--name',required=True);a=p.parse_args()
OUT=ROOT/'material/extension_deepening_20261024'/a.name;OUT.mkdir(exist_ok=False)
sources=[ROOT/'sim/tb_autoplay_terminal.sv',ROOT/'proj/src/user_source/hdl_source/SD/sd_card_bmp.v',ROOT/'material/extension_deepening_20261024/sd_card_bmp_reference.v']
results=[]
for count in [1,2,3,7,100,6000]:
 cmd=['D:/iverilog/bin/iverilog.exe','-g2012','-i','-s','tb_autoplay_terminal',f'-Ptb_autoplay_terminal.COUNT={count}','-o',str(OUT/f'{count}.vvp'),*map(str,sources)]
 c=subprocess.run(cmd,capture_output=True);(OUT/f'{count}_compile.log').write_bytes(c.stdout+c.stderr)
 assert not c.returncode,(c.stdout+c.stderr)
 s=subprocess.run(['D:/iverilog/bin/vvp.exe',str(OUT/f'{count}.vvp')],capture_output=True,timeout=60)
 (OUT/f'{count}.log').write_bytes(s.stdout+s.stderr);print(s.stdout.decode(),flush=True);assert not s.returncode
 results.append({'count':count,'returncode':s.returncode})
(OUT/'summary.json').write_text(json.dumps({'pass':True,'results':results,'source_sha256':{str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources}},indent=2))
