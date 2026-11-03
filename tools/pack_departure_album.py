"""Copy imagegen originals, encode board BMPs, and document the 22-photo sequence.

Only deterministic resizing/format encoding; no retouching or generated artwork.
Never accesses the TF card. Artwork itself is produced by built-in image_gen.
"""
from pathlib import Path
import hashlib
import html
import io
import json

from PIL import Image
from deploy_lyric28 import ROOT, validate_bmp
from deploy_departure_album import NAMES

FOLDER = ROOT / 'material/departure_story_20261023'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_artifact(path, payload):
    if path.exists() and path.read_bytes() != payload:
        raise ValueError('Refusing to replace a different image: ' + str(path))
    if not path.exists():
        path.write_bytes(payload)


def main():
    generation = json.loads((FOLDER / 'generated_sources.json').read_text(encoding='utf-8'))
    masters = FOLDER / 'masters'
    board = FOLDER / 'board'
    masters.mkdir(exist_ok=True)
    board.mkdir(exist_ok=True)
    assets = []
    cards = []
    for scene in generation['scenes']:
        original = Path(scene['generated_path'])
        master = masters / (scene['key'] + '.png')
        payload = original.read_bytes()
        write_artifact(master, payload)
        with Image.open(master) as source:
            size = source.size
            if abs(size[0] / size[1] - 4 / 3) > 0.005:
                raise ValueError('Not a 4:3 master: ' + scene['key'])
            # Preserve the whole composition: no crop, borders or image retouch.
            rgb = source.convert('RGB').resize((640, 480), Image.Resampling.LANCZOS)
            buf = io.BytesIO()
            rgb.save(buf, format='BMP')
        bmp = buf.getvalue()
        validate_bmp(bmp)
        target = board / scene['file']
        write_artifact(target, bmp)
        with Image.open(target) as check:
            if check.mode != 'RGB' or check.size != (640, 480) or check.tobytes() != rgb.tobytes():
                raise ValueError('BMP round-trip mismatch: ' + scene['file'])
        position = NAMES.index(scene['file']) + 1
        entry = dict(title=scene['title'], filename=scene['file'], playlist_position=position,
                     master=str(master.relative_to(FOLDER)).replace('\\', '/'),
                     board=str(target.relative_to(FOLDER)).replace('\\', '/'),
                     master_size=list(size), board_size=[640, 480],
                     master_sha256=sha(payload), board_sha256=sha(bmp), board_bytes=len(bmp))
        assets.append(entry)
        cards.append('<article><img src="' + entry['master'] + '" alt="' + html.escape(scene['title']) +
                     '"><div><b>' + html.escape(scene['title']) + '</b><span>播放第 ' + str(position) +
                     ' 张 · ' + scene['file'] + '</span></div></article>')
        print(scene['file'], position, len(bmp), entry['board_sha256'])
    manifest = dict(tool='built-in image_gen', started_date='2026-10-23',
                    encoding='640x480 RGB24 BI_RGB, bottom-up, 54-byte header',
                    added_count=4, playlist_count=len(NAMES),
                    added_bytes=sum(a['board_bytes'] for a in assets),
                    assets=assets, playlist=NAMES, first_particle_pair_preserved=NAMES[:2],
                    bitstream_change_required=False,
                    deployment_evidence='See deployment_*.json; this packer does not write the card.')
    (FOLDER / 'asset_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (FOLDER / 'playlist22.json').write_text(json.dumps(NAMES, ensure_ascii=False, indent=2), encoding='utf-8')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>离家与等待 · 四张故事新图</title><style>
*{box-sizing:border-box}body{margin:0;background:#1e211f;color:#f3eadb;font-family:"Microsoft YaHei",sans-serif;padding:32px 5vw}
header{max-width:1150px;margin:0 auto 28px}h1{font-size:30px;font-weight:600;margin:0 0 12px}p{color:#c8bdab;line-height:1.9;margin:8px 0}
main{max-width:1150px;margin:auto;display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:#2c302c;border-radius:10px;overflow:hidden}
img{display:block;width:100%;aspect-ratio:4/3;object-fit:contain}article div{padding:17px}b{display:block;font-size:19px}span{display:block;margin-top:8px;color:#c8bdab;font-size:13px}
footer{max-width:1150px;margin:26px auto;color:#c8bdab;line-height:1.8}@media(max-width:700px){main{grid-template-columns:1fr}body{padding:22px}}
</style><header><h1>离家与等待</h1><p>从临行的忙碌，到门口的目送，再到空巷与餐桌上的空座位。延续同一家三口的动画画风。</p>
<p>回家探望 → 收拾行李 → 整理围巾 → 背影送别 → 空巷等待 → 空着的座位 → 电话 → 老人入睡 → 团聚</p></header><main>'''
    page += ''.join(cards)
    page += '</main><footer>新增4张，播放总数22张。前两张及首个粒子转场保留；原稿无文字、无白边。<br>画面使用内置image_gen生成；BMP仅进行尺寸适配与格式编码。实际TF写入情况见同目录部署报告。</footer></html>'
    (FOLDER / 'preview.html').write_text(page, encoding='utf-8')


if __name__ == '__main__':
    main()
