"""Deploy LYRIC28.PCM plus the ALY1 LYRIC.IDX catalog to the 32 GB F: card.

Safety rules (same as the accepted ALB1 deployment): no formatting, no deletion,
no overwrite of a file whose bytes differ, a hash manifest of every existing root
file before the first write, contiguous-allocation checks, scan-range checks and
byte-level readback through a separate raw handle.

The FAT reader here is local to this project because the shared helper in
oral_album/tools decodes 8.3 names as ASCII and this card carries one non-ASCII
short entry. Its result is cross-checked against the LBAs that ALBUM.IDX already
records, so a parsing mistake cannot silently produce a wrong catalog.

Usage:
    python tools/deploy_lyric28.py              # dry run, prints the plan
    python tools/deploy_lyric28.py --apply      # back up, write, verify
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
CARD = Path('F:/')
PCM_SOURCE = ROOT / 'material/board/LYRIC.PCM'
PCM_NAME = 'LYRIC.PCM'
EXPECTED_SAMPLES = 15836464
CATALOG_NAME = 'LYRIC.IDX'
ALBUM_NAME = 'ALBUM.IDX'
PICTURES = ['PIC%04d.BMP' % i for i in range(1, 13)]
MAGIC = b'ALY1'
EXPECTED_SERIAL = 0x62653963
SCAN_LIMIT = 131071
PARTITION_OFFSET = 8192
RAW = '\\\\.\\F:'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode_catalog(sectors, audio):
    """512-byte ALY1 directory: magic, count, audio LBA, checksum, up to 64 LBAs."""
    if not 1 <= len(sectors) <= 64:
        raise ValueError('Catalog requires 1..64 pictures')
    if any(not 0 < value <= 0xFFFFFFFF for value in [audio] + list(sectors)):
        raise ValueError('Invalid LBA')
    if len(set(sectors)) != len(sectors):
        raise ValueError('Duplicate picture LBA')
    data = bytearray(512)
    checksum = (len(sectors) + audio + sum(sectors)) & 0xFFFFFFFF
    struct.pack_into('<4sIII', data, 0, MAGIC, len(sectors), audio, checksum)
    struct.pack_into('<' + 'I' * len(sectors), data, 16, *sectors)
    return bytes(data)


def decode_catalog(payload):
    magic, count, audio, checksum = struct.unpack_from('<4sIII', payload, 0)
    sectors = list(struct.unpack_from('<' + 'I' * count, payload, 16)) if count <= 64 else []
    return magic, count, audio, checksum, sectors


def validate_bmp(payload):
    if len(payload) != 921654 or payload[:2] != b'BM':
        raise ValueError('Expected a 640x480 24-bit BMP')
    if struct.unpack_from('<I', payload, 2)[0] != len(payload):
        raise ValueError('BMP declared length differs from the file length')
    if struct.unpack_from('<I', payload, 10)[0] != 54:
        raise ValueError('Unexpected pixel offset')
    if struct.unpack_from('<IiiHHI', payload, 14) != (40, 640, 480, 1, 24, 0):
        raise ValueError('Unsupported BMP header')


def fat_layout(disk):
    """Root-directory files with their cluster chains and physical first sector."""
    boot = disk.read(512)
    bps = struct.unpack_from('<H', boot, 11)[0]
    spc = boot[13]
    reserved = struct.unpack_from('<H', boot, 14)[0]
    fats = boot[16]
    fatsz = struct.unpack_from('<I', boot, 36)[0]
    root = struct.unpack_from('<I', boot, 44)[0]
    hidden = struct.unpack_from('<I', boot, 28)[0]
    assert bps == 512 and boot[82:90] == b'FAT32   ', 'Not a FAT32 volume'
    assert hidden == PARTITION_OFFSET, 'Unexpected volume offset; re-identify the card'
    data_start = reserved + fats * fatsz
    disk.seek(reserved * bps)
    fat = disk.read(fatsz * bps)

    def chain(start):
        result = []
        while 2 <= start < 0x0FFFFFF8:
            assert start not in result, 'FAT loop'
            result.append(start)
            start = struct.unpack_from('<I', fat, start * 4)[0] & 0x0FFFFFFF
        return result

    entries = {}
    long_parts = {}
    for cluster in chain(root):
        disk.seek((data_start + (cluster - 2) * spc) * bps)
        directory = disk.read(spc * bps)
        for offset in range(0, len(directory), 32):
            entry = directory[offset:offset + 32]
            if entry[0] == 0:
                break
            if entry[0] == 0xE5:
                long_parts = {}
                continue
            if entry[11] == 0x0F:
                if entry[0] & 0x40:
                    long_parts = {}
                raw = entry[1:11] + entry[14:26] + entry[28:32]
                long_parts[entry[0] & 0x1F] = raw.decode('utf-16le', 'replace')
                continue
            if entry[11] & 0x18:
                long_parts = {}
                continue
            name = entry[:8].decode('latin-1').rstrip()
            ext = entry[8:11].decode('latin-1').rstrip()
            name = name + ('.' + ext if ext else '')
            if long_parts:
                name = ''.join(long_parts[key] for key in sorted(long_parts))
                name = name.split('\0')[0].rstrip('\uffff')
            long_parts = {}
            first = ((struct.unpack_from('<H', entry, 20)[0] << 16)
                     | struct.unpack_from('<H', entry, 26)[0])
            clusters = chain(first) if first else []
            entries[name.lower()] = {
                'size': struct.unpack_from('<I', entry, 28)[0],
                'first_cluster': first,
                'clusters': clusters,
                'first_sector': hidden + data_start + (first - 2) * spc if first else 0,
                'contiguous': all(b == a + 1 for a, b in zip(clusters, clusters[1:])),
            }
    return entries, dict(bps=bps, spc=spc, cluster_bytes=bps * spc,
                         total_sectors=struct.unpack_from('<I', boot, 32)[0],
                         serial=struct.unpack_from('<I', boot, 67)[0])


def main():
    if not __debug__:
        raise RuntimeError('Refusing to deploy with Python optimizations enabled')
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()

    audio = PCM_SOURCE.read_bytes()
    magic, rate, samples, channels = struct.unpack_from('<4sIII', audio, 0)
    assert magic == b'APCM' and rate == 48000 and channels == 1
    assert len(audio) == 16 + 2 * samples, len(audio)
    assert samples == EXPECTED_SAMPLES, samples

    with open(RAW, 'rb', buffering=0) as disk:
        before, geometry = fat_layout(disk)
        assert geometry['serial'] == EXPECTED_SERIAL, 'Unexpected card serial %08X' % geometry['serial']
        for name in PICTURES:
            entry = before[name.lower()]
            assert entry['size'] == 921654 and entry['contiguous'], name
            assert entry['first_sector'] <= SCAN_LIMIT, name
            disk.seek((entry['first_sector'] - PARTITION_OFFSET) * 512)
            validate_bmp(disk.read(922112)[:921654])
        assert before[ALBUM_NAME.lower()]['size'] == 512

    # ALBUM.IDX was written and raw-readback verified by the accepted ALB1 deployment;
    # matching it proves this FAT parse addresses the same sectors.
    album = (CARD / ALBUM_NAME).read_bytes()
    album_magic, album_count, album_audio, album_sum, album_sectors = decode_catalog(album)
    assert album_magic == b'ALB1' and album_count == len(PICTURES), (album_magic, album_count)
    assert (album_count + album_audio + sum(album_sectors)) & 0xFFFFFFFF == album_sum
    assert album_sectors == [before[name.lower()]['first_sector'] for name in PICTURES], \
        'FAT parse disagrees with the ALB1 catalog already on the card'

    cluster_bytes = geometry['cluster_bytes']
    needed = ((len(audio) + cluster_bytes - 1) // cluster_bytes) * cluster_bytes + cluster_bytes
    assert shutil.disk_usage(CARD).free > needed + cluster_bytes * 4, 'Not enough free space'

    for name, payload in ((PCM_NAME, audio),):
        target = CARD / name
        if target.exists():
            assert digest(target) == sha(payload), \
                'A different %s already exists; refusing to overwrite' % name
    catalog = CARD / CATALOG_NAME
    if catalog.exists():
        current = catalog.read_bytes()
        # An all-zero 512-byte file is the placeholder this script creates before
        # the payload is written, so an interrupted run can simply be repeated.
        assert catalog.stat().st_size == 512 and current[:4] in (MAGIC, b'\0\0\0\0'), \
            'Existing LYRIC.IDX is not an ALY1 catalog; refusing to overwrite'

    print('Card F: serial %08X, %d sectors, cluster %d bytes, %d MB free'
          % (geometry['serial'], geometry['total_sectors'], cluster_bytes,
             shutil.disk_usage(CARD).free // (1024 * 1024)))
    print('ALY1 will point at the same 12 slots as ALB1 (LBAs %d..%d)'
          % (album_sectors[0], album_sectors[-1]))
    if not args.apply:
        print('Dry run only: card geometry, 12 BMPs, PCM and ALB1 cross-check passed; '
              'use --apply to write')
        return

    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup = ROOT / 'backups' / ('tf_lyric_' + stamp)
    backup.mkdir(parents=True)
    existing = {p.name: digest(p) for p in CARD.iterdir() if p.is_file()}
    for name, value in existing.items():
        shutil.copy2(CARD / name, backup / name)
        assert digest(backup / name) == value, 'Backup hash mismatch: ' + name
    (backup / 'fat_before.json').write_text(
        json.dumps(dict(geometry=geometry, files=before), indent=2), encoding='utf-8')

    target = CARD / PCM_NAME
    if not target.exists():
        with target.open('xb', buffering=0) as stream:
            if stream.write(audio) != len(audio):
                raise OSError('Short PCM write')
            os.fsync(stream.fileno())
    assert digest(target) == sha(audio)

    if not catalog.exists():
        with catalog.open('xb', buffering=0) as stream:
            if stream.write(bytes(512)) != 512:
                raise OSError('Short catalog write')
            os.fsync(stream.fileno())

    with open(RAW, 'rb', buffering=0) as disk:
        layout, geometry = fat_layout(disk)
    for name in PICTURES + [PCM_NAME]:
        assert layout[name.lower()]['contiguous'], 'Fragmented allocation: ' + name
    audio_lba = layout[PCM_NAME.lower()]['first_sector']
    sectors = [layout[name.lower()]['first_sector'] for name in PICTURES]
    assert sectors == album_sectors, 'Picture LBAs moved unexpectedly'
    payload = encode_catalog(sectors, audio_lba)
    with catalog.open('r+b', buffering=0) as stream:
        if stream.write(payload) != 512:
            raise OSError('Short catalog write')
        os.fsync(stream.fileno())
    assert catalog.read_bytes() == payload
    assert layout[CATALOG_NAME.lower()]['contiguous']
    assert layout[CATALOG_NAME.lower()]['first_sector'] <= SCAN_LIMIT, 'Catalog LBA outside scan range'

    with open(RAW, 'rb', buffering=0) as disk:
        after, _ = fat_layout(disk)
        disk.seek(0)
        disk.seek((after[PCM_NAME.lower()]['first_sector'] - PARTITION_OFFSET) * 512)
        assert disk.read(((len(audio) + 511) // 512) * 512)[:len(audio)] == audio, \
            'Raw PCM readback differs'
        disk.seek((after[CATALOG_NAME.lower()]['first_sector'] - PARTITION_OFFSET) * 512)
        assert disk.read(512) == payload, 'Raw catalog readback differs'
        disk.seek((after[PCM_NAME.lower()]['first_sector'] - PARTITION_OFFSET) * 512)
        # Raw volume reads must be sector aligned, so check the magic in a full sector.
        assert disk.read(512)[:4] == b'APCM', 'Catalog audio LBA does not start with APCM'
    for name, value in existing.items():
        if name.upper() in (PCM_NAME, CATALOG_NAME):
            continue
        assert digest(CARD / name) == value, 'Existing content changed: ' + name
        assert after[name.lower()] == before[name.lower()], 'Existing allocation changed: ' + name

    report = {
        'card': 'F:', 'volume_serial': '%08X' % geometry['serial'],
        'backup': str(backup), 'cluster_bytes': cluster_bytes,
        'catalog': CATALOG_NAME, 'catalog_magic': MAGIC.decode(),
        'catalog_lba': after[CATALOG_NAME.lower()]['first_sector'],
        'catalog_sha256': digest(catalog),
        'audio': PCM_NAME, 'audio_lba': audio_lba, 'audio_bytes': len(audio),
        'audio_samples': samples, 'audio_seconds': round(samples / 48000.0, 6),
        'audio_sha256': digest(target),
        'pictures': [{'file': name, 'lba': lba, 'sha256': digest(CARD / name)}
                     for name, lba in zip(PICTURES, sectors)],
        'checks': 'backup hashes, BMP headers, ALB1 cross-check, contiguous FAT chains, '
                  'scan-range LBA, raw sector readback, untouched existing files/allocation',
        'preserved': sorted(existing),
    }
    (ROOT / 'deployment_report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
