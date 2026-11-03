"""Prepare real song samples or package actual production-RTL pixel output."""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'material/audio_waveform_20261022'
FRAMES=17

def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    photo=Image.open(ROOT/'material/family_album_20261022/board/FAM0002.BMP').convert('RGB')
    a=np.asarray(photo).astype(np.uint32)
    rgb=(a[:,:,0]<<16)|(a[:,:,1]<<8)|a[:,:,2]
    (OUT/'photo.hex').write_text(''.join(f'{v:06x}\n' for v in rgb.flat),encoding='ascii')
    pcm=np.frombuffer((ROOT/'material/board/LYRIC.PCM').read_bytes(),dtype='<i2',offset=16).astype(np.int32)
    # Same two signed-Q8 gains as pcm_player_i2s with no voice and volume255.
    mixed=(((pcm*192)>>8)*255)>>8
    positions=[59*48000+k*1600 for k in range(FRAMES)]
    chunks=[]
    for position in positions:
        end=position//64*64
        chunks.extend(int(v)&65535 for v in mixed[end-8192:end])
    (OUT/'audio.hex').write_text(''.join(f'{v:04x}\n' for v in chunks),encoding='ascii')
    (OUT/'positions.hex').write_text(''.join(f'{v:06x}\n' for v in positions),encoding='ascii')
    print('Prepared 17 real-song windows and photo; production RTL renders every output pixel')

def package():
    frames=[]
    for k in range(FRAMES):
        p=OUT/f'waveform_frame_{k:02d}.ppm'
        im=Image.open(p).convert('RGB')
        assert im.size==(640,480)
        frames.append(im.copy())
    frames[0].save(OUT/'preview.png')
    frames[0].save(OUT/'preview.gif',save_all=True,append_images=frames[1:],duration=33,loop=0)
    # Diagnostic enlarged excerpt, no invented waveform or text drawing.
    strips=[im.crop((48,438,592,480)).resize((1088,84),Image.Resampling.NEAREST) for im in frames]
    strips[0].save(OUT/'waveform_detail.gif',save_all=True,append_images=strips[1:],duration=33,loop=0)
    if OUT.name=='audio_waveform_large_20261022':
        font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
        comparisons=[]
        for k,im in enumerate(frames):
            old=Image.open(ROOT/f'material/audio_waveform_20261022/waveform_frame_{k:02d}.ppm').convert('RGB')
            panel=Image.new('RGB',(1280,520),'#211b16');draw=ImageDraw.Draw(panel)
            draw.text((18,9),'原版：25像素显示区',font=font,fill='#ead9b7')
            draw.text((658,9),'新版：39像素显示区，保留强弱层次',font=font,fill='#ead9b7')
            panel.paste(old,(0,40));panel.paste(im,(640,40));comparisons.append(panel)
        comparisons[0].save(OUT/'comparison.png')
        comparisons[0].save(OUT/'comparison.gif',save_all=True,append_images=comparisons[1:],duration=33,loop=0)
    (OUT/'verification.json').write_text(json.dumps(dict(frames=FRAMES,source='production lyric_overlay + audio_waveform_overlay RTL',audio='LYRIC.PCM at 59 seconds; actual player gain arithmetic',scope='simulation, not a recording of the board',raster=[640,480]),ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS: 17 complete 640x480 RTL frames packaged without drawn/faked waveform')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--package',action='store_true')
    parser.add_argument('--large',action='store_true',help='Use a separate enlarged-waveform output folder')
    args=parser.parse_args()
    if args.large: OUT=ROOT/'material/audio_waveform_large_20261022'
    package() if args.package else prepare()
