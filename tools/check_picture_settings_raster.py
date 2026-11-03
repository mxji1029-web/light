"""Independent Chinese labels/digits/layout oracle, not the RTL formatter logic."""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'material/picture_settings_20261022'
font=np.array([int(v,16) for v in (OUT/'font.hex').read_text().split()],dtype=np.uint16).reshape(32,16)
glyphs=json.loads((OUT/'font_manifest.json').read_text(encoding='utf-8'))['glyphs']

def expected(base,active,b,c,selected,volume_level=10):
    result=base.copy()
    if not active:return result
    region=result[16:156,16:256].astype(np.uint16)
    result[16:156,16:256]=(region//4).astype(np.uint8)
    border=(128,100,68)
    result[16,16:256]=border;result[155,16:256]=border
    result[16:156,16]=border;result[16:156,255]=border
    lines=['画面调节',('>' if selected==0 else ' ')+'亮度 '+f'{b:+03d}',
           ('>' if selected==1 else ' ')+'对比度'+f'{c:3d}'+'%',
           ('>' if selected==2 else ' ')+'   '+f'{volume_level*10:3d}%',
           '长按KEY3退出','KEY2+4复原']
    for line,(text,top) in enumerate(zip(lines,[24,48,68,88,112,132])):
        color=(245,199,132) if line==0 or line==1+selected else (232,221,201)
        for col,ch in enumerate(text):
            for row,bits in enumerate(font[glyphs[ch]]):
                for x in range(16):
                    if int(bits)&(1<<(15-x)):result[top+row,32+col*16+x]=color
    # The new label is a geometric speaker; the original 32-glyph font stays fixed.
    image=Image.fromarray(result);draw=ImageDraw.Draw(image)
    color=(245,199,132) if selected==2 else (232,221,201)
    draw.rectangle((50,94,55,98),fill=color)
    draw.polygon([(55,96),(61,90),(61,102)],fill=color)
    draw.line([(65,92),(67,94),(67,98),(65,100)],fill=color)
    draw.line([(69,90),(73,94),(73,98),(69,102)],fill=color)
    result=np.array(image)
    for top,value,chosen in [(53,(b+64)//2,selected==0),(73,(c-50)*64//100,selected==1),
                             (93,volume_level*64//10,selected==2)]:
        result[top:top+7,176:240]=(66,60,52)
        result[top+1:top+6,177:min(239,176+value)]=(245,199,132) if chosen else (232,221,201)
        result[top,176:240]=border;result[top+6,176:240]=border
        result[top:top+7,176]=border;result[top:top+7,239]=border
        if top!=93:result[top:top+7,208]=border
    # Volume defaults to 100 percent at the right end, not a center-zero mark.
    result[91:102,239]=border
    return result

def check(actual,golden,name):
    mismatch=np.argwhere(np.any(actual!=golden,axis=2))
    assert len(mismatch)==0,(name,len(mismatch),mismatch[:8].tolist())

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sim-dir',type=Path,default=ROOT/'sim');parser.add_argument('--preview-dir',type=Path,default=OUT)
    parser.add_argument('--skip-pipeline',action='store_true',help='Explicitly check only OSD unit frames when real-photo pipeline frames have not been generated')
    args=parser.parse_args()
    base=np.full((480,640,3),(216,168,120),dtype=np.uint8)
    cases=[('settings_hidden.ppm',False,0,100,0,10),('settings_brightness.ppm',True,-64,150,0,10),
           ('settings_contrast.ppm',True,64,50,1,10),('settings_75.ppm',True,8,75,1,10),
           ('settings_volume_0.ppm',True,0,100,2,0),('settings_volume_50.ppm',True,0,100,2,5),
           ('settings_volume_100.ppm',True,0,100,2,10)]
    for name,active,b,c,s,v in cases:
        check(np.asarray(Image.open(args.sim_dir/name).convert('RGB')),expected(base,active,b,c,s,v),name)
    pipeline_pixels=0
    if args.skip_pipeline:
        print('SKIP real-photo pipeline panels: explicitly requested by --skip-pipeline')
    else:
        raw=np.asarray(Image.open(ROOT/'material/family_album_20261022/board/FAM0002.BMP').convert('RGB')).astype(np.int32)
        for frame,b,c,s in [(1,32,100,0),(2,0,125,1)]:
            image=np.clip(np.rint((raw-128)*c/100.0)+128+b,0,255).astype(np.uint8)
            golden=expected(image,True,b,c,s)
            actual=np.asarray(Image.open(args.preview_dir/f'settings_frame_{frame:02d}.ppm').convert('RGB'))
            check(actual[16:156,16:256],golden[16:156,16:256],f'pipeline frame {frame} panel')
            pipeline_pixels+=140*240
    print(f'PASS independent OSD oracle: {len(cases)*640*480:,} full-frame pixels + {pipeline_pixels:,} real-photo panel pixels; three selections, volume 0/50/100%, unchanged labels, restore hint and ties-even photo adjustment')

if __name__=='__main__':main()
