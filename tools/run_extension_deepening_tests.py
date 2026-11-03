"""Production-source integration and intentional numerical/UI behavior checks."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys

ROOT=Path(__file__).resolve().parents[1];RTL=ROOT/'proj/src/user_source/hdl_source'
parser=argparse.ArgumentParser();parser.add_argument('--name',required=True);args=parser.parse_args()
OUT=ROOT/'material'/args.name;OUT.mkdir(exist_ok=False)
IV='D:/iverilog/bin/iverilog.exe';VVP='D:/iverilog/bin/vvp.exe'
transport=['top_tf_hdmi_audio','picture_controls','photo_transition','pcm_player_i2s','pcm_mix16','I2S_receiver','lyric_audio_state','lyric_state_cdc','lyric_overlay','lyric_line_lookup','photo_adjust','picture_settings_osd','audio_waveform_overlay','video_rgb_to_axis_640x480','audio_spectrum_quality','spectrum_fft1024','spectrum_complex_ram','audio_volume_control','playback_status_cdc','playback_status_osd']
cases={
 'photo_transition':['photo_transition'],
 'multi_transition_control':['photo_transition'],
 'picture_controls':['picture_controls'],
 'controls_volume':['picture_controls'],
 'photo_adjust':['photo_adjust'],
 'picture_settings_osd':['picture_settings_osd'],
 'top_playback_pause':transport,
 'top_volume_status':transport,
 'display_ready_frame':['top_tf_hdmi_audio'],
 'picture_pipeline':transport[1:],
}
manifest={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in RTL.rglob('*') if p.is_file()}
results={}
def command(cmd,label):
 r=subprocess.run([str(x) for x in cmd],cwd=OUT,capture_output=True,timeout=240)
 (OUT/f'{label}.log').write_bytes(r.stdout+r.stderr)
 print(label,'exit',r.returncode,(r.stdout+r.stderr).decode('utf-8',errors='replace')[-650:],flush=True)
 if r.returncode:raise RuntimeError(label)
 return r.returncode
for test,sources in cases.items():
 top='tb_'+test
 command([IV,'-g2012','-i','-s',top,'-o',OUT/f'{test}.vvp',ROOT/'sim'/f'{top}.v',*[RTL/f'{s}.v' for s in sources]],test+'_compile')
 results[test]=command([VVP,OUT/f'{test}.vvp'],test)
results['independent_ui']=command([sys.executable,ROOT/'tools/check_picture_settings_raster.py','--sim-dir',OUT,'--preview-dir',OUT],'independent_ui')
after={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in RTL.rglob('*') if p.is_file()}
assert manifest==after,'Production changed during regression'
(OUT/'summary.json').write_text(json.dumps({'pass':True,'checks':results,'sources':manifest},indent=2))
print('PASS production extension integration: 10 RTL configurations plus independent UI; source closure unchanged')
