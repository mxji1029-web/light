"""Independent integer geometry reference for simulation and preview checking.

The oracle has no clock, pipeline, frame latch, burst or address-generation
state. It checks those behaviors when the production reader is simulated.
"""
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[1]

def choose(style,p,x,y):
    if p<=0:return 0
    if p>=256:return 1
    gx,gy=x//16,y//8
    hx=(gx*40503)&65535;hy=(gy*34283)&65535
    value=hx^hy;h=(value&255)^(value>>8);noise=h^(h>>3)
    row_noise=(hy&255)^(hy>>8)
    dx=abs(gx*16+8-320);dy=abs(gy*8+4-240)
    if style==0:return int(noise<p)
    if style in (3,9):
        q=256-p if style==9 else p
        radius=max(0,q*25//16+(noise&31)-16)
        inside=dx*dx+dy*dy<radius*radius
        return int(not inside if style==9 else inside)
    if style==7:
        dx=abs((gx%8)*16+8-64);dy=abs((gy%16)*8+4-64)
        radius=max(0,p*3//8+(noise&7)-4)
        return int(dx*dx+dy*dy<radius*radius)
    score={
        1:gx*24+(noise&127),
        2:gx*13+gy*8+(noise&63),
        4:(gx%8)*128+(noise&127),
        5:(59-gy)*16+(noise&127),
        6:(dx//8)*13+(dy//4)*8+(noise&63),
        8:gx*22+(row_noise&127),
        10:max((dx//8)*24,(dy//4)*16)+(noise&127),
        11:(gy%8)*128+(noise&127),
    }[style]
    return int(score<p*4)

def main():
    oracle=ROOT/'sim/multi_transition_oracle.hex'
    oracle.write_text(''.join(f'{choose(s,p,x,y)}\n' for s in range(12) for p in range(257)
                             for y in range(0,48,8) for x in range(0,64,16)),encoding='ascii')
    verified=0
    for s in range(12):
        path=ROOT/f'sim/multi_masks/style_{s:02d}.bin'
        if not path.exists():continue
        actual=path.read_bytes();expected=[]
        for frame in range(17):
            u=frame/16;p=frame*16 if s==0 else round(256*(3*u*u-2*u*u*u))
            expected.extend(choose(s,p,x,y) for y in range(0,480,8) for x in range(0,640,16))
        assert actual==bytes(expected),f'RTL mask differs from independent geometry: style {s}'
        verified+=1
    print(f'PASS independent oracle: {12*257*24} pipeline lookup cells; {verified} full-resolution RTL previews matched')

if __name__=='__main__':main()
