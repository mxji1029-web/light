"""Require real TD completion and fresh artifacts; TD sometimes returns0 on errors."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,sys
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--evidence-dir',type=Path,required=True)
p.add_argument('--output',type=Path,required=True);a=p.parse_args();e=a.evidence_dir.resolve()
run=ROOT/'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1'
name='HDMI1.4b_Transmitter_v1.0'
read=lambda f:f.read_text(encoding='utf-8-sig',errors='replace')
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
fail=[];report={'evidence_dir':str(e),'checks':{}}
def require(key,ok,detail):
 report['checks'][key]={'pass':bool(ok),'detail':detail}
 if not ok:fail.append(key)
for label in ['synthesis','physical']:
 native=e/(label+'_native_exit.txt');log=e/(label+'.log')
 require(label+'_native_exit',native.exists() and read(native).strip()=='0',read(native).strip() if native.exists() else 'missing')
 txt=read(log) if log.exists() else ''
 errors=[line for line in txt.splitlines() if re.search(r'\bERROR\s*:|^Error:|^invalid command',line)]
 require(label+'_no_errors',bool(txt) and not errors,errors[:8])
 if label=='physical':
  require('actual_bitgen',bool(re.search(r'finish command "bitgen\b',txt)),'TD must finish bitgen, not only return0')
  report['packed_mslices']=[int(x) for x in re.findall(r'(\d+) mslices,',txt)]
started_file=e/'build_started.json';stamp=None
if started_file.exists():stamp=datetime.datetime.fromisoformat(json.loads(read(started_file))['local_time']).timestamp()
require('build_timestamp',stamp is not None,'freeze timestamp required')
for label,file in [('bit',run/(name+'.bit')),('routed_timing',run/'final_timing.rpt'),('physical_area',run/(name+'_phy.area'))]:
 fresh=file.exists() and stamp is not None and file.stat().st_mtime>=stamp
 require(label+'_fresh',fresh,str(file))
 if fresh:report[label]={'path':str(file),'bytes':file.stat().st_size,'sha256':sha(file)}
manifest_file=e/'build_input_sha256.json';differences=[]
if manifest_file.exists():
 manifest=json.loads(read(manifest_file))
 differences=[rel for rel,s in manifest.items() if not (ROOT/rel).exists() or sha(ROOT/rel)!=s]
 report['producer_inputs']=len(manifest)
require('producer_unchanged',manifest_file.exists() and not differences,differences)
if report['checks']['routed_timing_fresh']['pass']:
 timing=read(run/'final_timing.rpt')
 report['timing_status']={k:v for k,v in re.findall(r'(SWNS|STNS|HWNS|HTNS):\s*([-\d.]+)ns',timing[:2500])}
 report['timing_signed_off']=all(float(v)>=0 for k,v in report['timing_status'].items() if k.endswith('WNS'))
report['pass']=not fail;report['failed_checks']=fail
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(('PASS verified fresh TD bit/report/source binding' if report['pass'] else 'FAIL no deliverable: '+', '.join(fail)))
sys.exit(0 if report['pass'] else 1)
