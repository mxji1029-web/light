"""Asset-level regression for the full-song lyric board build.

Checks the delivered PCM, the glyph/event/sentence ROM images, the 300 ms
hand-off rule, and the copies embedded in RTL against
material/board/timeline.json.
Run: python tools/verify_lyric_assets.py
"""
from pathlib import Path
import json
import re
import struct

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / 'material/lyrics_preview'
HDL = ROOT / 'proj/src/user_source/hdl_source'
PCM = ROOT / 'material/board/LYRIC.PCM'
TL = ROOT / 'material/board/timeline.json'
SAMPLES = 15836464
TAIL = 14400
GLYPH_SLOTS = 256
EVENT_SLOTS = 512
LINE_SLOTS = 64


def block_text(text, begin, end):
    return text[text.index(begin) + len(begin):text.index(end)].strip()


def block(path, begin, end):
    return block_text(path.read_text(encoding='utf-8'), begin, end)


def check_transition_params():
    """The top used to hard-code FADE_R/G/B = 242/233/214, which silently
    defeated every change made in photo_transition's defaults. Keep the
    instantiation parameter-free."""
    src = (HDL / 'top_tf_hdmi_audio.v').read_text(encoding='utf-8')
    start = src.index('photo_transition #(')
    block = src[start:src.index(') u_photo_transition', start)]
    for banned in ('.FADE_R', '.FADE_G', '.FADE_B', '.FADE_FRAMES', '.GRAIN_SHIFT'):
        assert banned not in block, 'top overrides %s; use the module default' % banned
    print('PASS: top leaves the transition parameters at their module defaults')


def main():
    check_transition_params()
    raw = PCM.read_bytes()
    magic, rate, count, channels = struct.unpack_from('<4sIII', raw, 0)
    assert magic == b'APCM', magic
    assert (rate, channels) == (48000, 1), (rate, channels)
    assert count == SAMPLES, count
    assert len(raw) == 16 + 2 * count, (len(raw), count)
    assert count % 2 == 0 and count < (1 << 24)

    song = json.loads(TL.read_text(encoding='utf-8'))
    assert song['samples'] == count
    chars, events, lines = song['chars'], song['events'], song['lines']
    assert len(chars) <= GLYPH_SLOTS and len(events) <= EVENT_SLOTS and len(lines) <= LINE_SLOTS
    assert 200 <= len(chars), len(chars)
    assert all(0 <= event['line'] < len(lines) for event in events)

    # 1. glyph ROM equals an independent render of the delivered character set.
    #    The table is delivered as four 8-bit slices (see build_lyric_board.py).
    slices = [[int(word, 16) for word in (HDL / ('lyric_font%d.hex' % lane)).read_text().split()]
              for lane in range(4)]
    assert all(len(part) == GLYPH_SLOTS * 32 for part in slices), [len(p) for p in slices]
    rows = [sum((slices[lane][i] & 0xFF) << (8 * lane) for lane in range(4))
            for i in range(GLYPH_SLOTS * 32)]
    font = ImageFont.truetype(str(PREVIEW / 'MaShanZheng-Regular.ttf'), 30)
    expected = []
    for char in chars:
        glyph = Image.new('L', (32, 32))
        draw = ImageDraw.Draw(glyph)
        box = draw.textbbox((0, 0), char, font=font)
        draw.text(((32 - (box[2] - box[0])) // 2 - box[0],
                   (32 - (box[3] - box[1])) // 2 - box[1]), char, font=font, fill=255)
        assert glyph.getbbox(), char
        for y in range(32):
            expected.append(sum(1 << (31 - x) for x in range(32)
                                if glyph.getpixel((x, y)) >= 96))
    expected.extend([0] * (GLYPH_SLOTS * 32 - len(expected)))
    assert rows == expected, 'lyric_font.hex differs from the font render'
    assert not any(rows[len(chars) * 32:]), 'glyph ROM padding is not blank'

    # 2. syllable table: {glyph[7:0], start[23:0], end[23:0]} packed in the generated case
    overlay = (HDL / 'lyric_overlay.v').read_text(encoding='utf-8')
    body = block_text(overlay, '// BEGIN GENERATED lyric_events', '// END GENERATED lyric_events')
    table = {int(slot): int(word, 16) for slot, word in
             re.findall(r"9'd(\d+): event_word_c=56'h([0-9A-Fa-f]+);", body)}
    index = {char: i for i, char in enumerate(chars)}
    for number, event in enumerate(events):
        assert event['char'] in index, event
        assert 0 <= event['start'] < event['end'] <= count, event
        wanted = (index[event['char']] << 48) | (event['start'] << 24) | event['end']
        assert table.pop(number, None) == wanted, 'syllable %d differs from the TTML' % number
    assert not table, 'leftover syllable slots: %r' % sorted(table)[:5]

    # 3. sentence table: 300 ms tail capped by the next sentence start
    table = [int(word, 16) for word in (HDL / 'lyric_lines.hex').read_text().split()]
    assert len(table) == LINE_SLOTS, len(table)
    lookup = (HDL / 'lyric_line_lookup.v').read_text(encoding='utf-8')
    generated = {int(slot): int(word, 16) for slot, word in re.findall(
        r"7'd(\d+): entry_c=64'h([0-9A-Fa-f]+);",
        block_text(lookup, '// BEGIN GENERATED lyric_lines', '// END GENERATED lyric_lines'))}
    base = 0
    for number, line in enumerate(lines):
        own = [event for event in events if event['line'] == number]
        assert line['base'] == base and line['count'] == len(own), (number, line)
        assert line['start'] == own[0]['start'] and 1 <= line['count'] <= 31
        stop = min(own[-1]['end'] + TAIL,
                   lines[number + 1]['start'] if number + 1 < len(lines) else count)
        assert line['stop'] == stop, (number, line['stop'], stop)
        expected_word = (line['start'] << 40) | (line['stop'] << 16) | (line['base'] << 7) | line['count']
        assert table[number] == expected_word, (number, table[number], expected_word)
        assert generated.get(number) == expected_word, \
            'sentence %d differs from lyric_lines.hex' % number
        base += len(own)
    assert base == len(events)
    assert not any(table[len(lines):]), 'sentence table padding is not blank'

    # 4. sample count copied into the RTL
    length = "localparam [23:0] LYRIC_SAMPLES=24'd%d;" % count
    assert (HDL / 'lyric_length.vh').read_text(encoding='ascii').strip() == length
    assert block(HDL / 'top_tf_hdmi_audio.v', '// BEGIN GENERATED lyric_length.vh',
                 '// END GENERATED lyric_length.vh') == length
    assert re.search(r"SAMPLES=24'd%d\b" % count,
                     (HDL / 'lyric_audio_state.v').read_text(encoding='utf-8'))

    # 5. the renderer must be sized for this table
    for lane in range(4):
        assert 'font%d[0:%d]' % (lane, GLYPH_SLOTS * 32 - 1) in overlay, 'glyph ROM size drifted'
    assert '{event_word[55:48],row_signed[4:0]}' in overlay, 'glyph field drifted'
    assert len(generated) <= LINE_SLOTS, 'sentence table overflow'

    print('PASS: %d samples (%.1f s), %d glyphs, %d syllables, %d sentences; ROM and RTL in sync'
          % (count, count / 48000.0, len(chars), len(events), len(lines)))


if __name__ == '__main__':
    main()