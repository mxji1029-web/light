"""Append four departure pictures and commit the verified 22-picture ALY1 index.

Default is read-only. --apply backs up every existing root file, appends only
missing DEP files, verifies FAT allocation and raw reads, and writes LYRIC.IDX
in place LAST. No formatting, deletion, raw device writes or board programming.
The existing 64-picture firmware needs no rebuild. Interrupted append files are
retained for inspection; a different existing DEP file is never overwritten.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import struct

from deploy_lyric28 import (
    ROOT, CARD, RAW, EXPECTED_SERIAL, PARTITION_OFFSET, SCAN_LIMIT,
    EXPECTED_SAMPLES, fat_layout, validate_bmp, encode_catalog, decode_catalog,
    digest,
)

FOLDER = ROOT / 'material/departure_story_20261023'
PACK = FOLDER / 'board'
OLD_NAMES = ([f'PIC{i:04d}.BMP' for i in range(1, 11)] +
             ['FIX00011.BMP', 'FIX00012.BMP'] +
             [f'FAM{i:04d}.BMP' for i in range(1, 7)])
ADDED = [f'DEP{i:04d}.BMP' for i in range(1, 5)]
NAMES = ([f'PIC{i:04d}.BMP' for i in range(1, 9)] +
         ['DEP0001.BMP', 'PIC0009.BMP', 'DEP0002.BMP', 'DEP0003.BMP',
          'DEP0004.BMP', 'PIC0010.BMP', 'FIX00011.BMP', 'FIX00012.BMP'] +
         [f'FAM{i:04d}.BMP' for i in range(1, 7)])


def snapshot():
    with open(RAW, 'rb', buffering=0) as disk:
        files, geometry = fat_layout(disk)
    # fat_layout also checks FAT32, 512-byte sectors and partition offset 8192.
    if geometry['serial'] != EXPECTED_SERIAL:
        raise ValueError('Different card: refusing deployment')
    return files, geometry


def check_extent(entry, geometry):
    if not entry['contiguous']:
        raise ValueError('Fragmented file: firmware requires continuous sectors')
    first, size = entry['first_sector'], entry['size']
    end = first + (size + 511) // 512
    if size <= 0 or first < PARTITION_OFFSET or end > PARTITION_OFFSET + geometry['total_sectors']:
        raise ValueError('File extent outside the verified card volume')
    if len(entry['clusters']) * geometry['cluster_bytes'] < size:
        raise ValueError('FAT chain shorter than declared file length')


def read_raw(entry, geometry):
    check_extent(entry, geometry)
    size = entry['size']
    with open(RAW, 'rb', buffering=0) as disk:
        disk.seek((entry['first_sector'] - PARTITION_OFFSET) * 512)
        data = disk.read(((size + 511) // 512) * 512)[:size]
    if len(data) != size:
        raise IOError('Short raw read')
    return data


def validate_catalog_order(payload, files):
    if len(payload) != 512:
        raise ValueError('Expected an existing 512-byte LYRIC.IDX')
    magic, count, audio, checksum, sectors = decode_catalog(payload)
    if (magic != b'ALY1' or count not in (18, 22) or
            checksum != ((count + audio + sum(sectors)) & 0xffffffff)):
        raise ValueError('Unexpected ALY1 catalog header, count or checksum')
    if audio != files['lyric.pcm']['first_sector']:
        raise ValueError('Unexpected catalog audio pointer')
    expected = OLD_NAMES if count == 18 else NAMES
    if sectors != [files[name.lower()]['first_sector'] for name in expected]:
        raise ValueError('Unexpected photo ordering: inspect before deployment')
    return count


def check_index_entry(files, geometry):
    entry = files['lyric.idx']
    check_extent(entry, geometry)
    if entry['size'] != 512 or entry['first_sector'] > SCAN_LIMIT:
        raise ValueError('Catalog outside the firmware discovery range')


def verified_payload(name, files, geometry):
    payload = read_raw(files[name.lower()], geometry)
    if hashlib.sha256(payload).hexdigest() != digest(CARD / name):
        raise IOError('Raw file readback mismatch: ' + name)
    return payload


def validate_current(files, geometry):
    check_index_entry(files, geometry)
    original = verified_payload('LYRIC.IDX', files, geometry)
    count = validate_catalog_order(original, files)
    audio = verified_payload('LYRIC.PCM', files, geometry)
    if (len(audio) != 16 + EXPECTED_SAMPLES * 2 or
            struct.unpack_from('<4sIII', audio) != (b'APCM', 48000, EXPECTED_SAMPLES, 1)):
        raise ValueError('Unexpected full-song PCM header or sample count')
    for name in OLD_NAMES if count == 18 else NAMES:
        validate_bmp(verified_payload(name, files, geometry))
    return original, count, hashlib.sha256(audio).hexdigest()


def verify_preserved(before, before_layout, current_layout, ignore_index=False):
    for name, expected in before.items():
        if name.lower() not in current_layout or current_layout[name.lower()] != before_layout[name.lower()]:
            raise ValueError('Original file allocation changed: ' + name)
        if not (ignore_index and name.lower() == 'lyric.idx'):
            if digest(CARD / name) != expected:
                raise ValueError('Original file changed: ' + name)


def commit_catalog(original, payload, before, before_layout):
    if len(original) != 512 or len(payload) != 512:
        raise ValueError('Catalog commit requires exactly 512 bytes')
    current, geometry = snapshot()
    verify_preserved(before, before_layout, current, ignore_index=True)
    attempted = False
    try:
        with (CARD / 'LYRIC.IDX').open('r+b', buffering=0) as stream:
            if stream.read() != original:
                raise ValueError('Catalog changed during deployment')
            stream.seek(0)
            attempted = True
            if stream.write(payload) != 512:
                raise IOError('Short catalog write')
            os.fsync(stream.fileno())
        current, geometry = snapshot()
        if current['lyric.idx'] != before_layout['lyric.idx']:
            raise ValueError('Catalog allocation changed after write')
        if read_raw(current['lyric.idx'], geometry) != payload:
            raise IOError('Catalog raw readback mismatch')
        verify_preserved(before, before_layout, current, ignore_index=True)
    except Exception as original_error:
        if attempted:
            try:
                current, geometry = snapshot()  # Re-identify before rollback.
                if current['lyric.idx'] != before_layout['lyric.idx']:
                    raise ValueError('Catalog allocation changed: refusing unsafe rollback')
                with (CARD / 'LYRIC.IDX').open('r+b', buffering=0) as stream:
                    if stream.write(original) != 512:
                        raise IOError('Short catalog rollback')
                    os.fsync(stream.fileno())
                if read_raw(current['lyric.idx'], geometry) != original:
                    raise IOError('Catalog rollback raw readback mismatch')
            except Exception as rollback_error:
                raise RuntimeError('Catalog rollback failed; restore verified backup before use: '
                                   + str(rollback_error)) from original_error
        raise


def catalog_for(files, geometry):
    check_index_entry(files, geometry)
    for name in NAMES:
        validate_bmp(verified_payload(name, files, geometry))
    return encode_catalog([files[name.lower()]['first_sector'] for name in NAMES],
                          files['lyric.pcm']['first_sector'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='back up, append and commit after checks')
    args = parser.parse_args()
    if not __debug__:
        raise RuntimeError('Run without Python -O; FAT validation is required')

    source = {}
    for name in ADDED:
        source[name] = (PACK / name).read_bytes()
        validate_bmp(source[name])
    source_hashes = {name: hashlib.sha256(data).hexdigest() for name, data in source.items()}
    files, geometry = snapshot()
    original, count, music_sha = validate_current(files, geometry)
    for name in ADDED:
        if (CARD / name).exists():
            if digest(CARD / name) != source_hashes[name]:
                raise ValueError('Different file already exists: ' + name)
            if verified_payload(name, files, geometry) != source[name]:
                raise IOError('New file raw readback mismatch: ' + name)

    cluster = geometry['cluster_bytes']
    needed = sum(((len(source[n]) + cluster - 1) // cluster) * cluster
                 for n in ADDED if not (CARD / n).exists())
    if shutil.disk_usage(CARD).free < needed + cluster * 4:
        raise ValueError('Insufficient free space on card')
    print('Verified card %08X: %d -> 22 photos; music SHA256 %s' %
          (geometry['serial'], count, music_sha))
    print('Order: ' + ', '.join(NAMES))
    if not args.apply:
        print('PASS dry run: read-only; four local BMPs validated. No files were changed.')
        return

    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    FOLDER.mkdir(parents=True, exist_ok=True)
    report_path = FOLDER / ('deployment_' + stamp + '.json')
    report = dict(timestamp=stamp, card=str(CARD), geometry=geometry,
                  old_count=count, picture_count=22, pictures=NAMES,
                  source_sha256=source_hashes, music_sha256=music_sha,
                  original_catalog_sha256=hashlib.sha256(original).hexdigest(),
                  catalog_lba=files['lyric.idx']['first_sector'],
                  hardware_download_performed=False)
    if count == 22:
        if catalog_for(files, geometry) != original:
            raise ValueError('Existing 22-picture catalog does not match target')
        report.update(status='already_deployed_verified', card_writes=False,
                      catalog_sha256=hashlib.sha256(original).hexdigest())
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print('PASS: already deployed; card unchanged. Report: ' + str(report_path))
        return

    before = {path.name: digest(path) for path in CARD.iterdir() if path.is_file()}
    index_name = next(name for name in before if name.lower() == 'lyric.idx')
    if before[index_name] != hashlib.sha256(original).hexdigest():
        raise ValueError('Catalog changed before backup')
    backup = ROOT / 'backups' / ('tf_departure_' + stamp)
    backup.mkdir(parents=True, exist_ok=False)
    backup_files = backup / 'files'
    backup_files.mkdir()
    for name, expected in before.items():
        shutil.copy2(CARD / name, backup_files / name)
        if digest(backup_files / name) != expected:
            raise IOError('Backup hash mismatch: ' + name)
    (backup / 'manifest.json').write_text(json.dumps(before, ensure_ascii=False, indent=2), encoding='utf-8')
    (backup / 'fat_before.json').write_text(json.dumps(dict(files=files, geometry=geometry), indent=2), encoding='utf-8')
    report.update(backup=str(backup), backup_files=str(backup_files), original_files_sha256=before)
    try:
        fresh, fresh_geometry = snapshot()
        if fresh_geometry != geometry:
            raise ValueError('Card geometry changed after backup')
        verify_preserved(before, files, fresh)
        for name, data in source.items():
            fresh, fresh_geometry = snapshot()
            if fresh_geometry != geometry:
                raise ValueError('Card changed before appending picture')
            if not (CARD / name).exists():
                with (CARD / name).open('xb', buffering=0) as stream:
                    if stream.write(data) != len(data):
                        raise IOError('Short picture write: ' + name)
                    os.fsync(stream.fileno())
            if digest(CARD / name) != source_hashes[name]:
                raise IOError('New picture hash mismatch: ' + name)

        after, after_geometry = snapshot()
        verify_preserved(before, files, after)
        payload = catalog_for(after, after_geometry)
        if digest(CARD / 'LYRIC.PCM') != music_sha:
            raise ValueError('Music changed before catalog commit')
        for name, expected in source_hashes.items():
            if digest(CARD / name) != expected:
                raise ValueError('New picture changed before catalog commit: ' + name)
        # Include appended pictures in the final before/after hash and FAT checks.
        commit_before = dict(before)
        commit_before.update(source_hashes)
        commit_layout = dict(files)
        commit_layout.update({name.lower(): after[name.lower()] for name in ADDED})
        commit_catalog(original, payload, commit_before, commit_layout)
        # commit_catalog checks all original allocation/hash invariants and raw index.
        report.update(status='deployed_verified', card_writes=True,
                      catalog_sha256=hashlib.sha256(payload).hexdigest(),
                      picture_lbas=[after[n.lower()]['first_sector'] for n in NAMES],
                      previous_files_unchanged_except_catalog=True,
                      catalog_lba_unchanged=True)
    except Exception as error:
        report.update(status='failed', error=str(error),
                      recovery='Check the original index backup and retained appended files; do not delete or format.')
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        raise
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PASS: 22 continuous BMPs and index raw-read verified; prior files preserved.')
    print('Backup: ' + str(backup))
    print('Report: ' + str(report_path))


if __name__ == '__main__':
    main()
