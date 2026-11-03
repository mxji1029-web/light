"""Select the verified test tone or original music, without changing any image.

Dry run: python tools/switch_test_audio.py
Activate tone: python tools/switch_test_audio.py --apply
Restore music: python tools/switch_test_audio.py --mode music --apply
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import struct
from deploy_family_album import snapshot,read_raw,commit_catalog,NAMES
from deploy_lyric28 import ROOT,CARD,SCAN_LIMIT,digest,decode_catalog

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--mode',choices=('tone','music'),default='tone')
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    folder=ROOT/'material/audio_test_48k'
    source=folder/'TEST1K.PCM'
    verified=json.loads((folder/'verification.json').read_text(encoding='utf-8'))
    if digest(source)!=verified['files']['TEST1K.PCM']['sha256']:
        raise ValueError('Test tone differs from the verified source')
    raw_source=source.read_bytes()
    if struct.unpack_from('<4sIII',raw_source)!=(b'APCM',48000,480000,1) or len(raw_source)!=960016:
        raise ValueError('Unexpected test tone format')
    files,geometry=snapshot()
    original=(CARD/'LYRIC.IDX').read_bytes()
    magic,count,audio,checksum,sectors=decode_catalog(original)
    if magic!=b'ALY1' or count!=18 or checksum!=(count+audio+sum(sectors))&0xffffffff:
        raise ValueError('Unexpected album catalog')
    if original!=read_raw(files['lyric.idx']) or files['lyric.idx']['first_sector']>SCAN_LIMIT:
        raise ValueError('Catalog not discoverable or raw read differs')
    if sectors!=[files[name.lower()]['first_sector'] for name in NAMES]:
        raise ValueError('Picture sectors/order changed; inspect first')
    allowed_audio={files['lyric.pcm']['first_sector']}
    if 'test1k.pcm' in files:
        allowed_audio.add(files['test1k.pcm']['first_sector'])
    if audio not in allowed_audio:
        raise ValueError('Unknown currently selected audio')
    if (CARD/'TEST1K.PCM').exists() and digest(CARD/'TEST1K.PCM')!=digest(source):
        raise ValueError('Different TEST1K.PCM already exists')
    print('Verified F: serial %08X, 18 pictures; requested mode %s'%(geometry['serial'],args.mode))
    if not args.apply:
        print('Dry run only; use --apply to back up and switch the audio pointer')
        return
    if shutil.disk_usage(CARD).free<2*1024*1024:
        raise ValueError('Not enough free space')
    stamp=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime('%Y%m%d_%H%M%S')
    backup=ROOT/'backups'/('tf_audio_'+args.mode+'_'+stamp)
    backup.mkdir(parents=True,exist_ok=False)
    before={p.name:digest(p) for p in CARD.iterdir() if p.is_file()}
    shutil.copy2(CARD/'LYRIC.IDX',backup/'LYRIC.IDX')
    if digest(backup/'LYRIC.IDX')!=before['LYRIC.IDX']:
        raise IOError('Catalog backup differs')
    (backup/'manifest.json').write_text(json.dumps(before,ensure_ascii=False,indent=2),encoding='utf-8')
    (backup/'fat_before.json').write_text(json.dumps(dict(files=files,geometry=geometry),indent=2),encoding='utf-8')
    snapshot()
    if args.mode=='tone' and not (CARD/'TEST1K.PCM').exists():
        with (CARD/'TEST1K.PCM').open('xb',buffering=0) as stream:
            if stream.write(raw_source)!=len(raw_source):
                raise IOError('Short tone write')
            os.fsync(stream.fileno())
    files,geometry=snapshot()
    target='test1k.pcm' if args.mode=='tone' else 'lyric.pcm'
    selected=files[target]
    raw=read_raw(selected)
    if args.mode=='tone' and raw!=raw_source:
        raise IOError('Tone raw readback differs')
    if args.mode=='music' and hashlib.sha256(raw).hexdigest()!=before['LYRIC.PCM']:
        raise IOError('Music raw readback differs')
    payload=bytearray(original)
    struct.pack_into('<II',payload,8,selected['first_sector'],
                     (count+selected['first_sector']+sum(sectors))&0xffffffff)
    payload=bytes(payload)
    if payload[:8]!=original[:8] or payload[16:]!=original[16:]:
        raise ValueError('Unexpected non-audio catalog change')
    commit_catalog(original,payload,before)
    report=dict(mode=args.mode,backup=str(backup),audio_lba=selected['first_sector'],
                picture_count=count,catalog_sha256=hashlib.sha256(payload).hexdigest(),
                audio_sha256=hashlib.sha256(raw).hexdigest(),pictures_unchanged=True,
                previous_files_unchanged_except_catalog=True,hardware_download_performed=False)
    (folder/('deployment_'+args.mode+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS: raw audio/catalog readback; 18 picture pointers and all previous files preserved')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    main()
