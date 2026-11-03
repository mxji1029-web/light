"""Wrap a 48 kHz / 16-bit / mono WAV as an APCM file for the TF card reader.

APCM layout expected by pcm_sd_reader.v:
    0  : "APCM"
    4  : sample rate  u32 LE
    8  : sample count u32 LE
    12 : channels     u32 LE
    16 : 16-bit signed little-endian mono samples
"""
from pathlib import Path
import struct
import sys


def wav_payload(path):
    raw = path.read_bytes()
    if raw[:4] != b'RIFF' or raw[8:12] != b'WAVE':
        raise SystemExit('not a RIFF/WAVE file: %s' % path)
    offset = 12
    fmt = None
    while offset + 8 <= len(raw):
        chunk_id = raw[offset:offset + 4]
        size = struct.unpack_from('<I', raw, offset + 4)[0]
        body = raw[offset + 8:offset + 8 + size]
        if chunk_id == b'fmt ':
            fmt = struct.unpack_from('<HHIIHH', body, 0)
        elif chunk_id == b'data':
            if fmt is None:
                raise SystemExit('data chunk before fmt chunk')
            tag, channels, rate, _, block_align, bits = fmt
            if (tag, channels, rate, bits) != (1, 1, 48000, 16):
                raise SystemExit('expected PCM 48k/16-bit/mono, got tag=%d ch=%d rate=%d bits=%d'
                                 % (tag, channels, rate, bits))
            return body
        offset += 8 + size + (size & 1)
    raise SystemExit('missing data chunk')


def main():
    source = Path(sys.argv[1] if len(sys.argv) > 1 else 'material/board/LYRIC.wav')
    target = Path(sys.argv[2] if len(sys.argv) > 2 else source.with_suffix('.PCM'))
    payload = wav_payload(source)
    if len(payload) % 2:
        raise SystemExit('odd byte count in PCM payload')
    samples = len(payload) // 2
    if samples >= (1 << 24):
        raise SystemExit('sample count %d does not fit the 24-bit lyric counter' % samples)
    header = struct.pack('<4sIII', b'APCM', 48000, samples, 1)
    target.write_bytes(header + payload)
    print('%s -> %s: %d samples, %.6f s, %d bytes'
          % (source.name, target.name, samples, samples / 48000.0, target.stat().st_size))


if __name__ == '__main__':
    main()
