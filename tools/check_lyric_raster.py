"""Check complete RTL frames against independent glyph placement; no old image trail."""
from pathlib import Path
import argparse
import re
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / 'proj/src/user_source/hdl_source'

def bounce(age, level, gentle):
    if not 0 <= age < 17408:
        return 0
    if gentle:
        table = [18,16,14,12,10,8,6,4,3,2,1,0,-1,-2,-3,-4,
                 -4,-4,-3,-3,-2,-2,-1,-1,0,0,0,0,0,0,0,0,0,0]
        value = table[age // 512]
        return value - ((-value * (level >> 6)) // 4 if value < 0 else 0)
    table = [29,22,15,9,4,0,-4,-7,-9,-8,-6,-4,-2,0,1,1,0]
    value = table[age // 1024]
    return value - (level >> 5 if value < 0 else 0)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gentle', action='store_true')
    args = parser.parse_args()
    events = dict((int(i), int(v,16)) for i,v in re.findall(
        r"9'd(\d+): event_word_c=56'h([0-9a-f]+)", (RTL/'lyric_overlay.v').read_text()))
    banks = [np.array([int(x,16) for x in (RTL/f'lyric_font{n}.hex').read_text().split()], dtype=np.uint32) for n in range(4)]
    rows = banks[0] | banks[1]<<8 | banks[2]<<16 | banks[3]<<24
    rendered = np.fromfile(ROOT/'sim/lyric_raster.bin',dtype=np.uint8).reshape(6,480,640)
    for frame, age0 in enumerate([0,4096,7168,8192,12288,13312]):
        position = 1371408 + age0
        expected = np.zeros((480,640),dtype=np.uint8)
        # First sung line: independently read its generated event descriptors.
        for col in range(10):
            event = events[5+col]
            glyph, start = event>>48, (event>>24)&0xffffff
            if position < start:
                continue
            top = 388+bounce(position-start,200,args.gentle)
            for y in range(32):
                for x in range(32):
                    expected[top+y,160+32*col+x] = (int(rows[glyph*32+y])>>(31-x))&1
        wrong = np.argwhere(rendered[frame]!=expected)
        assert len(wrong)==0, (frame,age0,len(wrong),wrong[:12].tolist())
    print('PASS 1,843,200 RTL pixels: exactly one glyph position, no duplicate/trailing rows')

if __name__ == '__main__':
    main()
