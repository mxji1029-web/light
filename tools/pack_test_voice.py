"""Pack locally generated spoken labels into a small signed 8-bit test ROM.

No online service, new dependency, or physical SD-card access is used.
8kHz is a resource-saving test format; final narration uses 48kHz/16-bit.
"""
import json
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RATE = 8000
SLOT = 8192


def convert(path):
    with wave.open(str(path), 'rb') as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2:
            raise ValueError(f'Expected mono signed 16-bit WAV: {path}')
        rate = source.getframerate()
        raw = source.readframes(source.getnframes())
    samples = list(struct.unpack('<' + 'h' * (len(raw) // 2), raw))
    # Strip only near-silent leading/trailing padding, retain 30ms margins.
    audible = [i for i, value in enumerate(samples) if abs(value) > 150]
    if not audible:
        raise ValueError(f'Empty or silent voice: {path}')
    margin = round(rate * .03)
    samples = samples[max(0, audible[0] - margin):min(len(samples), audible[-1] + margin + 1)]
    count = math.ceil(len(samples) * RATE / rate)
    if count > SLOT:
        raise ValueError(f'Voice needs {count} samples, exceeds slot {SLOT}; do not truncate speech')
    peak = max(abs(value) for value in samples)
    result = []
    for i in range(count):
        position = i * rate / RATE
        left = min(int(position), len(samples) - 1)
        right = min(left + 1, len(samples) - 1)
        value = samples[left] + (samples[right] - samples[left]) * (position - left)
        value = round(value * 110 / peak)
        result.append(max(-128, min(127, value)))
    return result, count


def main():
    rom = []
    metadata = []
    for index in range(1, 5):
        source = ROOT / 'material' / 'test_voice' / f'voice{index}.wav'
        samples, count = convert(source)
        rom.extend(samples + [0] * (SLOT - count))
        metadata.append({'photo_id': index - 1, 'spoken_label': f'第{index}张',
                         'samples': count, 'seconds': count / RATE})
    destination = ROOT / 'proj/src/user_source/hdl_source/rom/voice_test.hex'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(''.join(f'{value & 255:02x}\n' for value in rom), encoding='ascii')
    with wave.open(str(ROOT / 'material/test_voice/rom_preview.wav'), 'wb') as preview:
        preview.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        preview.writeframes(struct.pack('<' + 'h' * len(rom), *(value * 256 for value in rom)))
    (ROOT / 'material/test_voice/metadata.json').write_text(
        json.dumps({'rate': RATE, 'slot_samples': SLOT, 'rom_bytes': len(rom),
                    'voices': metadata}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(metadata, ensure_ascii=False))
    print(f'ROM: {len(rom)} bytes -> {destination}')


if __name__ == '__main__':
    main()
