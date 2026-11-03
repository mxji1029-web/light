"""Append repaired pictures and six portraits; commit the backed-up ALY1 index last.

Dry-run by default. Never deletes, formats, changes music, or replaces old BMPs.
New pictures may be beyond the scanner limit: only LYRIC.IDX must be discoverable.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import struct
from deploy_lyric28 import (ROOT, CARD, RAW, EXPECTED_SERIAL, PARTITION_OFFSET,
                           SCAN_LIMIT, fat_layout, validate_bmp,
                           encode_catalog, decode_catalog, digest)

PACK = ROOT / 'material/family_album_20261022/board'
NAMES = ([f'PIC{i:04d}.BMP' for i in range(1,11)]
         + ['FIX00011.BMP','FIX00012.BMP']
         + [f'FAM{i:04d}.BMP' for i in range(1,7)])
ADDED = NAMES[10:]

def snapshot():
    with open(RAW,'rb',buffering=0) as disk:
        files, geometry = fat_layout(disk)
    if geometry['serial'] != EXPECTED_SERIAL:
        raise ValueError('Different card: refusing to write')
    return files, geometry

def read_raw(entry):
    if not entry['contiguous']:
        raise ValueError('Fragmented file: index reader requires contiguous data')
    size = entry['size']
    with open(RAW,'rb',buffering=0) as disk:
        disk.seek((entry['first_sector']-PARTITION_OFFSET)*512)
        data = disk.read(((size+511)//512)*512)[:size]
    if len(data)!=size:
        raise IOError('Short raw read')
    return data

def catalog_for(files, geometry):
    sectors=[]
    for name in NAMES:
        entry=files[name.lower()]
        if not PARTITION_OFFSET <= entry['first_sector'] < PARTITION_OFFSET+geometry['total_sectors']:
            raise ValueError('Picture outside volume')
        payload=read_raw(entry)
        validate_bmp(payload)
        if hashlib.sha256(payload).hexdigest()!=digest(CARD/name):
            raise ValueError('Raw picture readback mismatch: '+name)
        sectors.append(entry['first_sector'])
    cat=files['lyric.idx']
    if cat['size']!=512 or not cat['contiguous'] or cat['first_sector']>SCAN_LIMIT:
        raise ValueError('Catalog outside the firmware discovery range')
    audio=files['lyric.pcm']
    if not audio['contiguous']:
        raise ValueError('Fragmented music')
    header=read_raw(audio)
    if struct.unpack_from('<4sIII',header)!=(b'APCM',48000,15836464,1):
        raise ValueError('Unexpected full-song PCM')
    return encode_catalog(sectors,audio['first_sector'])

def commit_catalog(original, payload, before):
    write_attempted=False
    try:
        with (CARD/'LYRIC.IDX').open('r+b',buffering=0) as stream:
            if stream.read()!=original:
                raise ValueError('Catalog changed during deployment')
            stream.seek(0);write_attempted=True
            if stream.write(payload)!=len(payload):
                raise IOError('Short catalog write')
            os.fsync(stream.fileno())
        files,geometry=snapshot()
        if read_raw(files['lyric.idx'])!=payload:
            raise IOError('Catalog raw readback mismatch')
        for name,sha in before.items():
            if name!='LYRIC.IDX' and digest(CARD/name)!=sha:
                raise IOError('Original file changed: '+name)
    except Exception:
        if write_attempted:
            files,geometry=snapshot()  # Includes card serial verification.
            with (CARD/'LYRIC.IDX').open('r+b',buffering=0) as stream:
                if stream.write(original)!=len(original):
                    raise IOError('Short catalog rollback')
                os.fsync(stream.fileno())
            if read_raw(files['lyric.idx'])!=original:
                raise IOError('Catalog rollback raw verification failed')
        raise

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    if not __debug__:
        raise RuntimeError('Run without Python -O')
    files,geometry=snapshot()
    original=(CARD/'LYRIC.IDX').read_bytes()
    magic,count,audio,checksum,sectors=decode_catalog(original)
    if magic!=b'ALY1' or count not in (12,18) or checksum!=(count+audio+sum(sectors))&0xffffffff:
        raise ValueError('Unexpected current ALY1 index')
    if original!=read_raw(files['lyric.idx']):
        raise ValueError('Existing catalog raw read mismatch')
    if audio!=files['lyric.pcm']['first_sector']:
        raise ValueError('Existing music LBA mismatch')
    expected_old=[f'PIC{i:04d}.BMP' for i in range(1,13)] if count==12 else NAMES
    if sectors!=[files[name.lower()]['first_sector'] for name in expected_old]:
        raise ValueError('Unexpected photo ordering: inspect before deployment')
    for name in ADDED:
        validate_bmp((PACK/name).read_bytes())
        if (CARD/name).exists() and digest(CARD/name)!=digest(PACK/name):
            raise ValueError('Different file already exists: '+name)
    if shutil.disk_usage(CARD).free < 16*1024*1024:
        raise ValueError('Insufficient free space')
    print('Verified F: serial %08X, %d -> 18 pictures; original music and BMP files retained'
          %(geometry['serial'],count))
    if not args.apply:
        print('Dry run: validated eight new BMPs. Use --apply to back up, append and verify.')
        return
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup=ROOT/'backups'/('tf_family_'+stamp)
    backup.mkdir(parents=True,exist_ok=False)
    before={p.name:digest(p) for p in CARD.iterdir() if p.is_file()}
    for name,sha in before.items():
        shutil.copy2(CARD/name,backup/name)
        if digest(backup/name)!=sha:
            raise IOError('Backup mismatch: '+name)
    (backup/'manifest.json').write_text(json.dumps(before,ensure_ascii=False,indent=2),encoding='utf-8')
    (backup/'fat_before.json').write_text(json.dumps(dict(files=files,geometry=geometry),indent=2),encoding='utf-8')
    snapshot()  # Re-identify the card after the backup, before the first mutation.
    for name in ADDED:
        if not (CARD/name).exists():
            with (CARD/name).open('xb',buffering=0) as stream:
                stream.write((PACK/name).read_bytes());os.fsync(stream.fileno())
        if digest(CARD/name)!=digest(PACK/name):
            raise IOError('New picture hash mismatch: '+name)
    files,geometry=snapshot()
    payload=catalog_for(files,geometry)
    # Commit a single existing 512-byte file only after all image readbacks pass.
    commit_catalog(original,payload,before)
    report=dict(backup=str(backup),pictures=NAMES,files=files,
                catalog_sha256=hashlib.sha256(payload).hexdigest(),
                music_sha256=before['LYRIC.PCM'],geometry=geometry)
    (ROOT/'material/family_album_20261022/deployment_report.json').write_text(
        json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS: 18 contiguous BMPs and catalog raw readback; all prior files preserved')
    print('Backup: '+str(backup))

if __name__=='__main__':
    main()
