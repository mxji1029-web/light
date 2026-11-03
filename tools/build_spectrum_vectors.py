"""Inline constants and independent direct-DFT plus fixed-point test vectors."""
from pathlib import Path
import math, json, random, re, sys
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'material/spectrum_bars_20261022';OUT.mkdir(exist_ok=True)
BINS=[2,3,4,6,8,12,17,24,34,48,68,96,136,192,272,384]
N=1024
coef=[round(2*math.cos(2*math.pi*k/N)*65536) for k in BINS]
cos=[round(math.cos(2*math.pi*k/N)*65536) for k in BINS]
sin=[round(math.sin(2*math.pi*k/N)*65536) for k in BINS]
parts=[]
for name,values in [('coefficient',coef),('cosine',cos),('sine',sin)]:
    parts.append(f'function signed[17:0] {name};input[3:0] index;begin\n case(index)')
    for index,v in enumerate(values):
        parts.append(f"  4'd{index}:{name}={'-' if v<0 else ''}18'sd{abs(v)};")
    parts.append(f' endcase\nend endfunction')
hdl=ROOT/'proj/src/user_source/hdl_source/audio_waveform_overlay.v'
original=hdl.read_text(encoding='utf-8')
text=re.sub(r'// COEFFICIENTS_BEGIN.*?// COEFFICIENTS_END', '// COEFFICIENTS_BEGIN\n'+'\n'.join(parts)+'\n// COEFFICIENTS_END',original,flags=re.S)
if '--check' in sys.argv:
    assert text==original,'Spectrum coefficients differ; regenerate explicitly before testing'
elif text!=original:
    hdl.write_text(text,encoding='utf-8')
def model(samples,dc_start=None):
    # DC removal (7.46Hz corner); initialize from the first real sample.
    acc=(samples[0]>>4)*1024 if dc_start is None else dc_start
    filtered=[0] if dc_start is None else []
    for value in (samples[1:] if dc_start is None else samples):
        x=value>>4;filtered.append(x-(acc>>10));acc+=((x*1024-acc)>>10)
    outputs=[]
    for index,k in enumerate(BINS):
        a=b=0
        for value in filtered:
            t=(a*coef[index]>>16)-b+value
            assert -(1<<28)<=t<(1<<28),'29-bit recurrence overflow'
            b,a=a,t
        real=a-(b*cos[index]>>16);imag=b*sin[index]>>16
        hi,lo=sorted([abs(real),abs(imag)],reverse=True)
        outputs.append((hi+lo//2)//16)
    return outputs,acc
def level(value):
    if value<16:return 0
    e=value.bit_length()-1
    return min(39,(e-4)*3+1+((value-(1<<e))*3>>e))
def tone(k,amp=20000):
    return [round(amp*math.sin(2*math.pi*k*n/N+.27)) for n in range(N)]
cases=[[0]*N,[22000]*N]+[tone(k) for k in BINS]
cases += [[round(9000*math.sin(2*math.pi*BINS[3]*n/N)+14000*math.sin(2*math.pi*BINS[12]*n/N)) for n in range(N)],
          [32767 if n%2 else -32768 for n in range(N)]]
rng=random.Random(20261022)
cases.append([rng.randrange(-32768,32768) for _ in range(N)])
song=[int(x,16) for x in (ROOT/'material/audio_waveform_large_20261022/audio.hex').read_text().split()]
song=[v-65536 if v>=32768 else v for v in song]
cases += [song[i*N:(i+1)*N] for i in range(8)]
expected=[];dc_state=None
for i,case in enumerate(cases):
    values,dc_state=model(case,dc_state if i>21 else None)
    expected.append(values)
for index in range(16):
    data=cases[index+2];k=BINS[index]
    re_part=sum((v>>4)*math.cos(2*math.pi*k*n/N) for n,v in enumerate(data))
    im_part=sum((v>>4)*math.sin(2*math.pi*k*n/N) for n,v in enumerate(data))
    exact=math.hypot(re_part,im_part)/16
    got=expected[index+2][index]
    assert .97*exact<=got<=1.14*exact,(index,got,exact)
    assert max(range(16),key=lambda j:expected[index+2][j])==index
    # DC filter initialization creates a real first-block transient (<6%).
    assert max(v for j,v in enumerate(expected[index+2]) if j!=index)<got*.06
assert max(expected[0])==0
assert max(expected[1])<300,'DC leakage unexpectedly large'
(OUT/'samples.hex').write_text(''.join(f'{v&65535:04x}\n' for case in cases for v in case))
(OUT/'magnitudes.hex').write_text(''.join(f'{v:08x}\n' for case in expected for v in case))
(OUT/'levels.hex').write_text(''.join(f'{level(v):02x}\n' for case in expected for v in case))
(OUT/'tone.hex').write_text(''.join(f'{v&65535:04x}\n' for v in tone(BINS[8])))
(OUT/'vectors.json').write_text(json.dumps(dict(block_size=N,sample_rate=48000,bins=BINS,
    frequencies_hz=[k*48000/N for k in BINS],blocks=len(cases),max_dc_magnitude=max(expected[1]),
    song_levels=[[level(v) for v in row] for row in expected[-8:]]),indent=2))
print(f'PASS: {len(cases)} blocks, all16 tones checked against independent direct DFT; DCmax {max(expected[1])}')
