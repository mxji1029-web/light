"""Prepare a self-contained audio/lyric visual prototype from user-owned inputs."""
from pathlib import Path
from PIL import Image, ImageFont, ImageDraw
import base64
import hashlib
import io
import json
import math
import re
import struct
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'material/lyrics_preview'
VIS = Path(r'C:\Users\季明鑫\.codex\visualizations\2026\10\20\01a158ed-3208-77b3-92d7-043d92ec0e88')


def mp3_frames(data):
    pos=0
    if data[:3]==b'ID3':
        size=0
        for b in data[6:10]:size=(size<<7)|(b&127)
        pos=10+size+(10 if data[5]&16 else 0)
    frames=[];t=0.0
    while pos+4<=len(data):
        h=int.from_bytes(data[pos:pos+4],'big')
        version=(h>>19)&3;layer=(h>>17)&3;bi=(h>>12)&15;si=(h>>10)&3
        if h>>21!=2047 or version==1 or layer!=1 or bi in (0,15) or si==3:
            pos+=1;continue
        rate=[44100,48000,32000][si]//({3:1,2:2,0:4}[version])
        kbps=([0,32,40,48,56,64,80,96,112,128,160,192,224,256,320][bi] if version==3
              else [0,8,16,24,32,40,48,56,64,80,96,112,128,144,160][bi])
        size=(144000 if version==3 else 72000)*kbps//rate+((h>>9)&1)
        if pos+size>len(data):break
        duration=(1152 if version==3 else 576)/rate
        frames.append((t,pos,size,duration));t+=duration;pos+=size
    if len(frames)<100:raise ValueError('Unable to parse this MPEG Layer III file')
    return frames,t


def seconds(s):
    result=0.0
    for part in s.rstrip('s').split(':'):result=result*60+float(part)
    return result


def data_url(data,mime):return 'data:'+mime+';base64,'+base64.b64encode(data).decode()


def main():
    OUT.mkdir(parents=True,exist_ok=True);VIS.mkdir(parents=True,exist_ok=True)
    lyrics=Path('F:/歌词.txt').read_text(encoding='utf-8-sig')
    if not lyrics.strip():raise ValueError('User lyric file is empty')
    (OUT/'user_lyrics.txt').write_text(lyrics,encoding='utf-8')
    source=OUT/'source_timing.ttml'
    tree=ET.parse(source)
    ns={'t':'http://www.w3.org/ns/ttml'}
    lines=[]
    compact=lambda s:re.sub(r'[\s，。！？、：:·—-]','',s)
    full_user=compact(lyrics)
    for element in tree.findall('.//t:p',ns)[:6]:
        words=[{'s':seconds(x.attrib['begin']),'e':seconds(x.attrib['end']),'c':''.join(x.itertext())}
               for x in element.findall('t:span',ns)]
        text=''.join(x['c'] for x in words)
        if compact(text) not in full_user:raise ValueError('Timing text does not match user lyrics: '+text)
        lines.append({'s':words[0]['s'],'e':words[-1]['e'],'words':words,'text':text})
    original=Path('F:/我记得 - 赵雷.mp3').read_bytes()
    frames,duration=mp3_frames(original)
    chosen=[f for f in frames if f[0]>=26.75 and f[0]<54.6]
    origin=chosen[0][0]
    clip=b''.join(original[p:p+n] for _,p,n,_ in chosen)
    (OUT/'preview_excerpt.mp3').write_bytes(clip)
    # Open licensed calligraphic font; stored project-locally, never installed.
    fontpath=OUT/'MaShanZheng-Regular.ttf'
    if not fontpath.exists():
        urllib.request.urlretrieve('https://raw.githubusercontent.com/google/fonts/main/ofl/mashanzheng/MaShanZheng-Regular.ttf',fontpath)
    font=ImageFont.truetype(str(fontpath),58)
    chars=sorted(set(''.join(line['text'] for line in lines)))
    cell=80;cols=8;rows=math.ceil(len(chars)/cols)
    atlas=Image.new('RGBA',(cols*cell,rows*cell),(255,255,255,0));draw=ImageDraw.Draw(atlas)
    for i,ch in enumerate(chars):
        x=(i%cols)*cell+cell//2;y=(i//cols)*cell+cell//2
        draw.text((x,y),ch,font=font,anchor='mm',fill=(255,255,255,255))
    atlas.save(OUT/'glyph_atlas.png')
    backgrounds=[]
    picroot=ROOT.parent/'oral_album/material/tf_story_20261020_215537/all_12_bmp'
    for fname,label in [('01_02_first_steps.bmp','儿时 · 一步一步'),('04_10_bicycle.bmp','成长 · 有你在身后'),('05_12_dumplings.bmp','过年 · 一家人坐齐')]:
        im=Image.open(picroot/fname).convert('RGB');buf=io.BytesIO();im.save(buf,format='JPEG',quality=73,optimize=True)
        backgrounds.append({'src':data_url(buf.getvalue(),'image/jpeg'),'label':label})
    payload={'origin':origin,'duration':sum(x[3] for x in chosen),'lines':lines,'chars':chars,'cell':cell,'cols':cols,
             'atlas':data_url((OUT/'glyph_atlas.png').read_bytes(),'image/png'),
             'audio':data_url(clip,'audio/mpeg'),'backgrounds':backgrounds}
    template=(ROOT/'tools/lyric_preview.template.html').read_text(encoding='utf-8')
    html=template.replace('/*__PAYLOAD__*/',json.dumps(payload,ensure_ascii=False))
    dest=VIS/'listening-album-lyrics.html'
    dest.write_text(html,encoding='utf-8')
    if dest.stat().st_size>=1_000_000:raise ValueError('Inline preview exceeds 1MB')
    standalone='<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>听见岁月 · 歌词预览</title><style>body{margin:0;padding:16px;background:#171411}</style></head><body>'+html+'</body></html>'
    (OUT/'preview.html').write_text(standalone,encoding='utf-8')
    # Timing assets remain reusable when the FPGA implementation is added.
    events=[]
    for li,line in enumerate(lines):
        for x,w in enumerate(line['words']):
            events.append({'start_sample':round(w['s']*48000),'end_sample':round(w['e']*48000),
                           'line':li,'column':x,'glyph':chars.index(w['c'])})
    (OUT/'word_events.json').write_text(json.dumps(events,ensure_ascii=False,indent=2),encoding='utf-8')
    metadata={'original_mp3_sha256':hashlib.sha256(original).hexdigest(),'original_duration_frame_estimate':duration,
              'excerpt_origin':origin,'excerpt_duration':payload['duration'],'excerpt_bytes':len(clip),
              'matched_user_lyric_lines':len(lines),'events':len(events),'unique_glyphs':len(chars),
              'font':'Ma Shan Zheng / SIL OFL 1.1','glyph_rasterization':'58px in 80px cell',
              'timing_source':'https://github.com/amll-dev/amll-ttml-db/blob/main/ncm-lyrics/1974443814.ttml',
              'timing_contributor':'vistre','preview_bytes':dest.stat().st_size,
              'alignment_status':'Published word timings matched to user lyric text; audio version offset requires listening; player has +/-1s adjustment',
              'tf_or_bitstream_modified':False}
    (OUT/'metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(metadata,ensure_ascii=False,indent=2));print(dest)


if __name__=='__main__':main()
