"""Preserve generated masters and encode 4:3 board-ready BMPs without retouching."""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw
from deploy_lyric28 import ROOT, validate_bmp

def main():
    selected=json.loads((ROOT/'material/photo_inspection/generated_files.json').read_text(encoding='utf-8'))
    folder=ROOT/'material/family_album_20261022'
    masters=folder/'masters';board=folder/'board'
    masters.mkdir(parents=True,exist_ok=True);board.mkdir(exist_ok=True)
    names={'restore11':'FIX00011.BMP','restore12':'FIX00012.BMP'}
    names.update({f'family{i:02d}':f'FAM{i:04d}.BMP' for i in range(1,7)})
    sheet=Image.new('RGB',(960,520),'#202020');draw=ImageDraw.Draw(sheet)
    for key,name in names.items():
        master=masters/(key+'.png')
        if master.exists() and master.read_bytes()!=Path(selected[key]).read_bytes():
            raise ValueError('Different master already exists: '+str(master))
        shutil.copy2(selected[key],master)
        im=Image.open(master).convert('RGB')
        if abs(im.width/im.height-4/3)>0.005:
            raise ValueError('Unexpected aspect ratio: '+key)
        im=im.resize((640,480),Image.Resampling.LANCZOS)
        im.save(board/name,format='BMP')
        validate_bmp((board/name).read_bytes())
        if key.startswith('family'):
            i=int(key[-2:])-1
            sheet.paste(im.resize((320,240)),((i%3)*320,(i//3)*260))
            age=[1,6,12,18,30,45][i]
            draw.text(((i%3)*320+8,(i//3)*260+242),f'{name}  son age {age}',fill='white')
        print(name,im.size,(board/name).stat().st_size)
    sheet.save(folder/'family_contact.png')

if __name__=='__main__':
    main()
