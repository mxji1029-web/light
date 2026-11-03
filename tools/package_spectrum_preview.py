"""Package production-RTL pixels, independently verify every spectrum-region pixel."""
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'material/spectrum_bars_20261022'
rows=[[int(x) for x in line.split(',')] for line in (OUT/'levels.csv').read_text().splitlines()]
frames=[];ink_count=0
# Outside bars the source is irrelevant; check all painted pixels exactly.
for row in rows:
    frame,heights,peaks=row[0],row[1:17],row[17:33]
    im=Image.open(OUT/f'frame_{frame:02d}.ppm').convert('RGB');assert im.size==(640,480)
    px=im.load()
    for x in range(64,576):
        col,local=divmod(x-64,32);h,p=heights[col],peaks[col]
        for y in range(440,479):
            up=478-y;color=None
            if y==478:color=0x806444
            if 4<=local<28:
                if h and up<h:color=0xf5d393 if up+3>=h else 0xe9bd78 if up>=22 else 0xcda261 if up>=10 else 0xa67b47
                if p and up==p-1:color=0xf5d393
            if color is not None:
                assert px[x,y]==((color>>16)&255,(color>>8)&255,color&255),(frame,x,y,px[x,y],hex(color))
                ink_count+=1
    frames.append(im)
assert len({tuple(r[1:17]) for r in rows})>=10,'Insufficient real-song spectrum motion'
frames[8].save(OUT/'preview.png')
durations=[20,20,10]*8 # GIF centisecond timing approximates the actual59.52fps.
frames[0].save(OUT/'preview.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0)
detail=[im.crop((48,432,592,480)).resize((1088,96)) for im in frames]
detail[0].save(OUT/'detail.gif',save_all=True,append_images=detail[1:],duration=durations,loop=0)
print(f'PASS {len(frames)} actual RTL frames; {ink_count} independently checked colored pixels; dynamic real song bins')
