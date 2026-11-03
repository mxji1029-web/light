"""Compose actual RTL mask outputs with the twelve existing album photos."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np
import json

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'material/multi_transitions'
NAMES=['原版粒子','横向柔幕','斜向柔幕','中心光圈','竖向百叶','向上柔幕',
       '菱形光圈','光斑渐展','风吹柔幕','环抱收拢','相纸舒展','横向百叶']
def main():
    OUT.mkdir(exist_ok=True)
    pictures=sorted((ROOT.parent/'oral_album/material/tf_story_20261020_215537/all_12_bmp').glob('*.bmp'))
    assert len(pictures)==12
    photos=[np.array(Image.open(p).convert('RGB')) for p in pictures]
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    frames_by_style=[];labels=[]
    for s,name in enumerate(NAMES):
        masks=np.frombuffer((ROOT/f'sim/multi_masks/style_{s:02d}.bin').read_bytes(),dtype=np.uint8).reshape(17,60,40)
        assert not masks[0].any() and masks[-1].all()
        assert np.all(masks[:-1]<=masks[1:])
        a,b=photos[s],photos[(s+1)%12]
        frames=[]
        for mask in masks:
            full=np.repeat(np.repeat(mask,8,axis=0),16,axis=1).astype(bool)
            rgb=np.where(full[:,:,None],b,a)
            assert np.all(np.all(rgb==a,axis=2)|np.all(rgb==b,axis=2))
            frames.append(Image.fromarray(rgb).resize((320,240),Image.Resampling.LANCZOS))
        label=f'{s+1:02d} → {(s+1)%12+1:02d}  {name}'
        labels.append(label);frames_by_style.append(frames)
        decorated=[]
        for frame in frames:
            panel=Image.new('RGB',(320,268),'#211b16');panel.paste(frame,(0,0))
            ImageDraw.Draw(panel).text((10,244),label,font=font,fill='#ead9b7');decorated.append(panel)
        decorated[0].save(OUT/f'{s:02d}.gif',save_all=True,append_images=decorated[1:],duration=[350]+[67]*15+[450],loop=0)
    sheet=Image.new('RGB',(960,1072),'#211b16')
    for s,frames in enumerate(frames_by_style):
        panel=Image.new('RGB',(320,268),'#211b16');panel.paste(frames[8],(0,0))
        ImageDraw.Draw(panel).text((10,244),labels[s],font=font,fill='#ead9b7')
        sheet.paste(panel,((s%3)*320,(s//3)*268))
    sheet.save(OUT/'contact_sheet.png')
    montage=[]
    for f in range(17):
        canvas=Image.new('RGB',(640,536),'#211b16')
        for k,s in enumerate([0,3,7,8]):
            px=(k%2)*320;py=(k//2)*268;canvas.paste(frames_by_style[s][f],(px,py))
            ImageDraw.Draw(canvas).text((px+10,py+244),labels[s],font=font,fill='#ead9b7')
        montage.append(canvas)
    montage[0].save(OUT/'overview.gif',save_all=True,append_images=montage[1:],duration=[350]+[67]*15+[450],loop=0)
    html='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>听见岁月 · 转场预览</title><style>body{background:#211b16;color:#ead9b7;font:16px sans-serif;margin:28px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}img{max-width:100%}</style><h1>听见岁月 · 十二种转场</h1><p>实际 RTL 遮罩与相册照片合成预览，未叠加板上歌词。首对粒子保持原样，其余统一缓入缓出。</p><main>'
    html+=''.join(f'<article><img src="{s:02d}.gif" alt="{label}"></article>' for s,label in enumerate(labels))+'</main></html>'
    (OUT/'index.html').write_text(html,encoding='utf-8')
    (OUT/'verification.json').write_text(json.dumps({'styles':12,'frames_per_style':17,'raster':[640,480],
        'mask_source':'sim/tb_render_multi_masks.v -> production transition_mask.v',
        'checks':['old/new endpoints','monotonic source change','every output pixel from one of the two source photos'],
        'scope':'RTL visualization; not hardware validation'},ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS twelve real-photo previews: endpoints, monotonicity, original-source pixels; no transition background')

if __name__=='__main__':main()
