"""Deploy standard BMP files and ALB1 catalog without formatting or raw writes.

For the identified 32GB FAT32 F: card only. File allocations are validated using
read-only FAT metadata and payload reads. Existing files are backed up first.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import struct
import datetime

ROOT = Path(__file__).resolve().parents[1]
CARD = Path('F:/')
HELPER = ROOT.parent / 'oral_album/tools/prepare_story_tf.py'


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def encode_catalog(sectors, audio):
    if not 1 <= len(sectors) <= 64:
        raise ValueError('Catalog requires 1..64 pictures')
    if any(not 0 < x <= 0xFFFFFFFF for x in [audio] + list(sectors)):
        raise ValueError('Invalid LBA')
    if len(set(sectors)) != len(sectors):
        raise ValueError('Duplicate picture LBA')
    data = bytearray(512)
    checksum = (len(sectors) + audio + sum(sectors)) & 0xFFFFFFFF
    struct.pack_into('<4sIII', data, 0, b'ALB1', len(sectors), audio, checksum)
    struct.pack_into('<' + 'I'*len(sectors), data, 16, *sectors)
    return bytes(data)


def validate_bmp(b):
    if len(b)!=921654 or b[:2]!=b'BM':
        raise ValueError('Expected 640x480 RGB BMP')
    if struct.unpack_from('<I',b,2)[0]!=len(b):
        raise ValueError('BMP declared file length differs from actual length')
    if struct.unpack_from('<I',b,10)[0]!=54 or struct.unpack_from('<IiiHHI',b,14)!=(40,640,480,1,24,0):
        raise ValueError('Unsupported BMP header')


def main():
    if not __debug__:
        raise RuntimeError('Do not run deployment with Python optimizations; validation is required')
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', required=True, type=Path)
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()
    pictures = sorted(args.source.glob('*.bmp'))
    encode_catalog(list(range(1, len(pictures)+1)), 100)
    for p in pictures:
        b = p.read_bytes()
        validate_bmp(b)
    spec = importlib.util.spec_from_file_location('tf_layout_helper', HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    before = helper.fat_layout()
    assert all(n in before for n in helper.NAMES + ['bgm.pcm'])
    with open(r'\\.\F:', 'rb', buffering=0) as disk:
        boot = disk.read(512)
    total_sectors = struct.unpack_from('<I', boot, 32)[0]
    assert 60_000_000 < total_sectors < 65_000_000, 'Unexpected card geometry'
    cluster_bytes = struct.unpack_from('<H', boot, 11)[0] * boot[13]
    volume_serial = struct.unpack_from('<I', boot, 67)[0]
    round_cluster = lambda size: ((size + cluster_bytes - 1)//cluster_bytes)*cluster_bytes
    assert shutil.disk_usage(CARD).free > len(pictures)*round_cluster(921654)+cluster_bytes*4
    audio = (CARD/'bgm.pcm').read_bytes()
    assert audio[:4] == b'APCM'
    assert struct.unpack_from('<I', audio, 4)[0] == 48000
    assert struct.unpack_from('<I', audio, 12)[0] == 1
    assert len(audio) == 16 + struct.unpack_from('<I', audio, 8)[0]*2
    assert before['bgm.pcm']['contiguous']
    print(f'Validated {len(pictures)} BMPs; cluster={cluster_bytes}; volume serial={volume_serial:08X}')
    if not args.apply:
        print('Dry run only; use --apply to deploy')
        return
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = ROOT/'backups'/('tf_'+stamp)
    backup.mkdir(parents=True)
    existing = {p.name: digest(p) for p in CARD.iterdir() if p.is_file()}
    for name, h in existing.items():
        shutil.copy2(CARD/name, backup/name)
        assert digest(backup/name) == h
    (backup/'fat_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    catalog = CARD/'ALBUM.IDX'
    if not catalog.exists():
        with catalog.open('xb',buffering=0) as f:
            f.write(bytes(512));os.fsync(f.fileno())
    else:
        assert catalog.stat().st_size == 512 and catalog.read_bytes()[:4] == b'ALB1'
    layout = helper.fat_layout()
    assert layout['album.idx']['contiguous'] and layout['album.idx']['first_sector'] <= 131071
    mapped = []
    for i, source in enumerate(pictures,1):
        target = CARD/f'PIC{i:04d}.BMP'
        if target.exists():
            # Never silently replace an unrelated same-name file.
            assert digest(target) == digest(source), f'Existing file differs: {target}'
        else:
            with target.open('xb',buffering=0) as f:
                written=f.write(source.read_bytes())
                if written!=921654: raise OSError("Short BMP write")
                os.fsync(f.fileno())
        mapped.append((source,target))
    layout = helper.fat_layout()
    for source,target in mapped:
        entry=layout[target.name.lower()]
        assert entry['contiguous'] and entry['size'] == 921654, f'Fragmented BMP: {target}'
        assert entry['first_sector']+1801 <= total_sectors+8192
        assert digest(source) == digest(target)
    sectors=[layout[t.name.lower()]['first_sector'] for _,t in mapped]
    audio_lba=layout['bgm.pcm']['first_sector']
    payload=encode_catalog(sectors,audio_lba)
    with catalog.open('r+b',buffering=0) as f:
        written=f.write(payload)
        if written!=512: raise OSError("Short catalog write")
        os.fsync(f.fileno())
    assert catalog.read_bytes()==payload
    after=helper.fat_layout()
    # Raw device access is read-only and sector-aligned.
    with open(r'\\.\F:', 'rb', buffering=0) as disk:
        for source,target in mapped:
            disk.seek((after[target.name.lower()]['first_sector']-8192)*512)
            assert disk.read(922112)[:921654] == source.read_bytes()
        disk.seek((after['album.idx']['first_sector']-8192)*512)
        assert disk.read(512)==payload
    for name,h in existing.items():
        if name.lower()!='album.idx':
            assert digest(CARD/name)==h, f'Existing content changed: {name}'
            assert after[name.lower()]==before[name.lower()], f'Existing allocation changed: {name}'
    report={
        'card':'F:', 'volume_serial':f'{volume_serial:08X}', 'backup':str(backup),
        'cluster_bytes':cluster_bytes, 'volume_bytes':shutil.disk_usage(CARD).total,
        'free_bytes_after':shutil.disk_usage(CARD).free,
        'catalog_lba':after['album.idx']['first_sector'], 'audio_lba':audio_lba,
        'catalog_sha256':digest(catalog), 'audio_sha256':digest(CARD/'bgm.pcm'),
        'pictures':[{'file':t.name,'source':s.name,'lba':lba,'sha256':digest(t)}
                    for (s,t),lba in zip(mapped,sectors)],
        'checks':'PASS: backup hashes, contiguous FAT chains, standard BMP headers, raw readback, preserved existing files',
        'capacity_empty_card_estimates':{
            'bmp_bytes':921654,'bmp_allocated_bytes':round_cluster(921654),
            'photos_only':shutil.disk_usage(CARD).total//round_cluster(921654),
            'photo_plus_mono_48k16_10s':shutil.disk_usage(CARD).total//(round_cluster(921654)+round_cluster(16+96000*10)),
            'photo_plus_mono_48k16_30s':shutil.disk_usage(CARD).total//(round_cluster(921654)+round_cluster(16+96000*30)),
            'photo_plus_stereo_48k16_30s':shutil.disk_usage(CARD).total//(round_cluster(921654)+round_cluster(16+192000*30)),
        },
    }
    (ROOT/'deployment_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
