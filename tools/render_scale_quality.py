"""Render real RTL nearest/bilinear frames and compare independent array math.

Never reads/writes a TF card. PPMs are simulation output, not board captures.
"""
from pathlib import Path
import hashlib,json,subprocess
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'material/scale_quality_20261023/render'
HDL=ROOT/'proj/src/user_source/hdl_source/SD'

def sample(a,w,h,quality):
 sh,sw,_=a.shape;x=np.arange(w,dtype=np.int64)*sw;y=np.arange(h,dtype=np.int64)*sh
 x0=x//w;y0=y//h;x1=np.minimum(x0+1,sw-1);y1=np.minimum(y0+1,sh-1)
 p=a[y0[:,None],x0[None,:]].astype(np.int64)
 if not quality:return p.astype(np.uint8)
 q=a[y0[:,None],x1[None,:]].astype(np.int64);r=a[y1[:,None],x0[None,:]].astype(np.int64);s=a[y1[:,None],x1[None,:]].astype(np.int64)
 fx=((x%w)*256//w)[None,:,None];fy=((y%h)*256//h)[:,None,None]
 u=(p*(256-fx)+q*fx+128)>>8;v=(r*(256-fx)+s*fx+128)>>8
 return ((u*(256-fy)+v*fy+128)>>8).astype(np.uint8)

def reference(a,quality):
 sh,sw,_=a.shape
 if not quality:return sample(a,640,480,False)
 if sw*480>sh*640:w,h=640,max(1,sh*640//sw)
 else:w,h=max(1,sw*480//sh),480
 result=np.zeros((480,640,3),dtype=np.uint8)
 left,top=(640-w)//2,(480-h)//2;result[top:top+h,left:left+w]=sample(a,w,h,True)
 return result

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 photo=Image.open(ROOT/'material/family_album_20261022/board/FAM0001.BMP').convert('RGB').resize((320,240),Image.Resampling.LANCZOS)
 portrait=Image.new('RGB',(256,512),'#f3e8d2');d=ImageDraw.Draw(portrait)
 d.ellipse((28,156,228,356),outline='#b94632',width=4)
 d.line((8,8,248,504),fill='#205e70',width=3)
 d.rectangle((0,0,255,511),outline='#8a7044',width=3)
 d.text((16,20),'PORTRAIT / CIRCLE',fill='#334444')
 records=[]; sources=[HDL/'bmp_read.v',HDL/'bmp_scale_stream.v',HDL/'bmp_scale_quality.v',HDL/'bmp_bilinear_stream.v']
 for name,image in [('family',photo),('portrait',portrait)]:
  path=OUT/(name+'.bmp');image.save(path);a=np.asarray(image)
  data=path.read_bytes();hexfile=OUT/(name+'.hex');hexfile.write_text(''.join(f'{b:02x}\n' for b in data)+('00\n'*512),encoding='ascii')
  pictures=[]
  for quality in [0,1]:
   stem=f'{name}_{quality}';raster=OUT/(stem+'.ppm');binary=OUT/(stem+'.vvp')
   command=['D:/iverilog/bin/iverilog.exe','-g2012','-s','tb_bmp_scaling',f'-Ptb_bmp_scaling.SW={image.width}',f'-Ptb_bmp_scaling.SH={image.height}',f'-Ptb_bmp_scaling.QUALITY={quality}','-Ptb_bmp_scaling.CHECK_PATTERN=0',f'-Ptb_bmp_scaling.INPUT_HEX="{hexfile.as_posix()}"',f'-Ptb_bmp_scaling.OUTPUT_PPM="{raster.as_posix()}"','-o',str(binary),str(ROOT/'sim/tb_bmp_scaling.v')]+[str(p) for p in sources]
   c=subprocess.run(command,capture_output=True,timeout=90);(OUT/(stem+'_compile.log')).write_bytes(c.stdout+c.stderr);assert c.returncode==0,stem
   c=subprocess.run(['D:/iverilog/bin/vvp.exe',str(binary)],capture_output=True,timeout=240);(OUT/(stem+'_run.log')).write_bytes(c.stdout+c.stderr);assert c.returncode==0,stem
   actual=Image.open(raster).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
   expected=reference(a,quality)
   assert np.array_equal(np.asarray(actual),expected),'RTL pixels differ from independent array oracle: '+stem
   actual.save(OUT/(stem+'.png'));pictures.append(actual)
  sheet=Image.new('RGB',(1280,512),'#20242a');d=ImageDraw.Draw(sheet)
  d.text((12,9),'PREVIOUS: STRETCH / NEAREST',fill='white');d.text((652,9),'NEW: ASPECT FIT / BILINEAR (RTL)',fill='white')
  sheet.paste(pictures[0],(0,32));sheet.paste(pictures[1],(640,32));sheet.save(OUT/(name+'_comparison.png'))
  # Detail enlargements deliberately use nearest display so interpolation artifacts remain visible.
  if name=='family':
   detail=Image.new('RGB',(1024,512),'black')
   for i,p in enumerate(pictures):detail.paste(p.crop((240,100,368,228)).resize((512,512),Image.Resampling.NEAREST),(i*512,0))
   detail.save(OUT/'family_detail.png')
  records.append(dict(source=path.name,sha256=hashlib.sha256(data).hexdigest(),pixels_checked=2*640*480,rtl_matches_integer_oracle=True))
 hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[ROOT/'sim/tb_bmp_scaling.v']}
 (OUT/'manifest.json').write_text(json.dumps(dict(records=records,source_sha256=hashes,kind='RTL simulation output, not hardware capture'),ensure_ascii=False,indent=2),encoding='utf-8')
 print('PASS: 1,228,800 actual RTL raster pixels match independent Q8/aspect oracle; family and portrait previews saved')

if __name__=='__main__':main()
