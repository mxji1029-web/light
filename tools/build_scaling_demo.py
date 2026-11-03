"""Make copyright-free local BMP fixtures and floor-nearest reference previews.

Writes only inside material/scaling_demo_20261023, never to a removable drive.
These BMPs are optional demonstration assets; the current TF catalog is untouched.
"""
from pathlib import Path
import hashlib
import json
import struct
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'material/scaling_demo_20261023'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    tiles = []
    for width, height, top_down in [(320,240,False),(800,600,False),(321,241,True)]:
        picture = Image.new('RGB', (width,height), '#f1e7d3')
        draw = ImageDraw.Draw(picture)
        colors = ['#c55e48','#d6af4f','#477c77','#4e638f']
        for y in range(2):
            for x in range(2):
                draw.rectangle((x*width//2,y*height//2,(x+1)*width//2-1,(y+1)*height//2-1), fill=colors[y*2+x])
        for y in range(0,height,17):
            draw.line((0,y,width-1,y), fill='#e8e1d3')
        draw.text((12,12), f'TOP LEFT {width}x{height}', fill='white')
        draw.text((12,height-22), 'BOTTOM LEFT', fill='white')
        draw.rectangle((0,0,width-1,height-1), outline='white', width=3)
        path = OUT / f'SCALE_{width}x{height}{"_TOPDOWN" if top_down else ""}.BMP'
        picture.save(path)
        if top_down:
            data = bytearray(path.read_bytes())
            offset = struct.unpack_from('<I',data,10)[0]
            stride = (width*3+3)&~3
            rows = [bytes(data[offset+y*stride:offset+(y+1)*stride]) for y in range(height)]
            data[offset:offset+height*stride] = b''.join(reversed(rows))
            struct.pack_into('<i',data,22,-height)
            path.write_bytes(data)
        # Compare in logical display coordinates, independent of BMP storage order.
        a = np.asarray(picture)
        output = a[(np.arange(480)*height//480)[:,None], np.arange(640)*width//640]
        preview = Image.fromarray(output)
        preview.save(OUT/(path.stem+'_640x480.png'))
        tiles.append(preview.resize((320,240)))
        records.append(dict(file=path.name,width=width,height=height,top_down=top_down,
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        with Image.open(path) as check:
            assert np.array_equal(np.asarray(check),a), 'BMP sign/row conversion failed'
    sheet = Image.new('RGB',(960,240),'black')
    for i,tile in enumerate(tiles):sheet.paste(tile,(i*320,0))
    sheet.save(OUT/'comparison.png')
    (OUT/'manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'PASS: 3 standard BMP demo assets including signed height and row padding: {OUT}')


if __name__ == '__main__':main()
