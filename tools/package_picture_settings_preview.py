"""Package actual full-pipeline RTL frames; labels only sit outside the raster."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'material/picture_settings_20261022'
names=['normal','brightness','contrast']
labels=['默认：亮度0 / 对比度100%','调亮：亮度+32 / 对比度100%','增强对比：亮度0 / 对比度125%']
frames=[]
sheet=Image.new('RGB',(960,276),'#211b16');draw=ImageDraw.Draw(sheet)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
for k,name in enumerate(names):
    image=Image.open(OUT/f'settings_frame_{k:02d}.ppm').convert('RGB')
    assert image.size==(640,480)
    image.save(OUT/f'{name}.png');frames.append(image)
    sheet.paste(image.resize((320,240)),(k*320,36))
    draw.text((k*320+8,8),labels[k],font=font,fill='#ead9b7')
frames[0].save(OUT/'preview.gif',save_all=True,append_images=frames[1:],duration=1800,loop=0)
sheet.save(OUT/'comparison.png')
print('PASS three actual key-driven photo/lyric/wave/Chinese OSD frames packaged')
