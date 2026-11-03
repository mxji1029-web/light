"""Regenerate the lyric assets for the whole song.

Sources: material/lyrics_preview/source_timing.ttml (45 sentences, 461 syllables)
         material/lyrics_preview/MaShanZheng-Regular.ttf
         material/board/LYRIC.PCM (APCM header carries the sample count)

Outputs: lyric_font0..3.hex   4 x 8192 bytes = 256 glyph slots x 32 rows, one
                              byte per row so TD maps each slice to 8192x1 banks
                              (a 32-bit array made TD use 1024x9 banks and lose
                              every 9th bit)
         the generated case tables inside lyric_overlay.v (syllable events) and
         lyric_line_lookup.v (sentence windows), so neither depends on TD's
         block-RAM packing
         lyric_lines.hex       same sentence table for tb_lyric_lines
         lyric_length.vh       sample count, plus the copy in top_tf_hdmi_audio.v

Timing rule (same as the approved browser preview):
  a sentence is replaced the moment the next one starts, otherwise the tail is
  kept for at most 300 ms so a long final vowel is not clipped early.

Run: python tools/build_lyric_board.py
"""
from pathlib import Path
import json
import struct
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / 'material/lyrics_preview'
HDL = ROOT / 'proj/src/user_source/hdl_source'
PCM = ROOT / 'material/board/LYRIC.PCM'

GLYPH_SLOTS = 256          # 8-bit glyph index -> {glyph[7:0], row[4:0]}
ROW_SLOTS = 32
EVENT_SLOTS = 512          # 9-bit event address
LINE_SLOTS = 64
TAIL_SAMPLES = 14400       # 300 ms at 48 kHz
NS = '{http://www.w3.org/ns/ttml}'
LENGTH_BEGIN = '// BEGIN GENERATED lyric_length.vh'
LENGTH_END = '// END GENERATED lyric_length.vh'
EVENTS_BEGIN = '// BEGIN GENERATED lyric_events'
EVENTS_END = '// END GENERATED lyric_events'
LINES_BEGIN = '// BEGIN GENERATED lyric_lines'
LINES_END = '// END GENERATED lyric_lines'


def parse_time(text):
    """TTML clock: "SS.mmm", "MM:SS.mmm" or "HH:MM:SS.mmm"."""
    seconds = 0.0
    for part in text.strip().split(':'):
        seconds = seconds * 60.0 + float(part)
    return seconds


# Title card for the 28 s intro: the first sung line is not before 28.571 s, and
# the judges should see the word-by-word caption immediately after power-up.
# (text, [start seconds], hold seconds)
INTRO = [
    ('我记得', [1.00, 1.80, 2.60], 0.70),
    ('赵雷', [5.00, 6.00], 0.90),
]


def load_song():
    """Return (sentences, glyphs, samples, events) for the whole song."""
    ttml = (PREVIEW / 'source_timing.ttml').read_text(encoding='utf-8')
    paras = ET.fromstring(ttml).findall('.//' + NS + 'p')
    samples = struct.unpack_from('<I', PCM.read_bytes(), 8)[0]
    sentences = []
    for text, times, hold in INTRO:
        words = []
        for char, second in zip(text, times):
            start = int(round(second * 48000))
            words.append(dict(char=char, start=start,
                              end=start + int(round(hold * 48000)), line=len(sentences)))
        sentences.append(words)
    for para in paras:
        index = len(sentences)
        spans = [span for span in para.findall(NS + 'span') if span.text]
        if not spans:
            continue
        spans.sort(key=lambda span: parse_time(span.get('begin')))
        words = []
        for span in spans:
            text = span.text.strip()
            if len(text) != 1:
                raise AssertionError('expected one character per syllable, got %r' % text)
            start = int(round(parse_time(span.get('begin')) * 48000))
            end = int(round(parse_time(span.get('end')) * 48000))
            if not 0 <= start < end <= samples:
                raise AssertionError('syllable %r outside the audio: %d..%d' % (text, start, end))
            words.append(dict(char=text, start=start, end=end, line=index))
        sentences.append(words)
    chars = sorted({word['char'] for words in sentences for word in words})
    if len(chars) > GLYPH_SLOTS:
        raise AssertionError('%d glyphs do not fit %d slots' % (len(chars), GLYPH_SLOTS))
    index = {char: i for i, char in enumerate(chars)}
    events = []
    for number, words in enumerate(sentences):
        for word in words:
            events.append(dict(glyph=index[word['char']], start=word['start'],
                               end=word['end'], line=number, char=word['char']))
    return sentences, chars, samples, events


def font_rows(chars):
    """One 32-bit row per scanline: bit 31 is the leftmost pixel."""
    font = ImageFont.truetype(str(PREVIEW / 'MaShanZheng-Regular.ttf'), 30)
    rows = []
    for char in chars:
        glyph = Image.new('L', (32, 32))
        draw = ImageDraw.Draw(glyph)
        box = draw.textbbox((0, 0), char, font=font)
        draw.text(((32 - (box[2] - box[0])) // 2 - box[0],
                   (32 - (box[3] - box[1])) // 2 - box[1]),
                  char, font=font, fill=255)
        assert glyph.getbbox(), char
        for y in range(ROW_SLOTS):
            rows.append(sum(1 << (31 - x) for x in range(32)
                            if glyph.getpixel((x, y)) >= 96))
    rows.extend([0] * (GLYPH_SLOTS * ROW_SLOTS - len(rows)))
    return rows


def event_words(events):
    """{glyph[7:0], start[23:0], end[23:0]} packed into 56 bits."""
    words = [(event['glyph'] << 48) | (event['start'] << 24) | event['end']
             for event in events]
    if len(words) > EVENT_SLOTS:
        raise AssertionError('%d events do not fit %d slots' % (len(words), EVENT_SLOTS))
    words.extend([0] * (EVENT_SLOTS - len(words)))
    return words


def sentence_lines(sentences, samples):
    """Windows with the accepted hand-off rule, plus the table words."""
    lines = []
    base = 0
    for index, words in enumerate(sentences):
        start = words[0]['start']
        end = words[-1]['end']
        stop = min(end + TAIL_SAMPLES,
                   sentences[index + 1][0]['start'] if index + 1 < len(sentences) else samples)
        count = len(words)
        if not 1 <= count <= 31:
            raise AssertionError('sentence %d has %d syllables' % (index, count))
        lines.append(dict(start=start, stop=stop, base=base, count=count))
        base += count
    if len(lines) > LINE_SLOTS:
        raise AssertionError('%d sentences do not fit %d slots' % (len(lines), LINE_SLOTS))
    words = [(line['start'] << 40) | (line['stop'] << 16) | (line['base'] << 7) | line['count']
             for line in lines]
    words.extend([0] * (LINE_SLOTS - len(words)))
    return lines, words


def event_case(words):
    """case() body for lyric_overlay.v: address -> packed syllable word."""
    body = [' event_word_c=56\'d0;', ' case(event_addr)']
    for index, word in enumerate(words[:EVENT_SLOTS]):
        if word:
            body.append("  9'd%d: event_word_c=56'h%014x;" % (index, word))
    body.append('  default: event_word_c=56\'d0;')
    body.append(' endcase')
    return '\n'.join(body)


def line_case(words):
    """case() body for lyric_line_lookup.v: index -> window word."""
    body = [' entry_c=64\'d0;', ' case(index)']
    for index, word in enumerate(words[:LINE_SLOTS]):
        if word:
            body.append("  7'd%d: entry_c=64'h%016x;" % (index, word))
    body.append('  default: entry_c=64\'d0;')
    body.append(' endcase')
    return '\n'.join(body)


def patch_block(path, begin, end, body):
    """Replace the generated body between two marker comments, preserving CRLF."""
    text = path.read_text(encoding='utf-8')
    head = text.index(begin) + len(begin)
    tail = text.index(end)
    updated = text[:head] + '\n' + body + '\n' + text[tail:]
    if updated == text:
        return False
    path.write_text(updated, encoding='utf-8')
    return True


def main():
    sentences, chars, samples, events = load_song()
    rows = font_rows(chars)
    words = event_words(events)
    lines, line_words = sentence_lines(sentences, samples)

    for lane in range(4):
        (HDL / ('lyric_font%d.hex' % lane)).write_text(
            ''.join('%02x\n' % ((row >> (8 * lane)) & 0xFF) for row in rows), encoding='ascii')
    (HDL / 'lyric_lines.hex').write_text(
        ''.join('%016x\n' % word for word in line_words), encoding='ascii')
    (HDL / 'lyric_length.vh').write_text(
        "localparam [23:0] LYRIC_SAMPLES=24'd%d;\n" % samples, encoding='ascii')

    touched = []
    if patch_block(HDL / 'lyric_overlay.v', EVENTS_BEGIN, EVENTS_END, event_case(words)):
        touched.append('lyric_overlay.v')
    if patch_block(HDL / 'lyric_line_lookup.v', LINES_BEGIN, LINES_END, line_case(line_words)):
        touched.append('lyric_line_lookup.v')
    if patch_block(HDL / 'top_tf_hdmi_audio.v', LENGTH_BEGIN, LENGTH_END,
                   "localparam [23:0] LYRIC_SAMPLES=24'd%d;" % samples):
        touched.append('top_tf_hdmi_audio.v')

    (ROOT / 'material/board/timeline.json').write_text(
        json.dumps(dict(samples=samples, chars=chars, lines=lines, events=events),
                   ensure_ascii=False, indent=2), encoding='utf-8')
    print('PASS: %d sentences, %d syllables, %d glyphs, %d samples (%.3f s); RTL %s'
          % (len(sentences), len(events), len(chars), samples, samples / 48000.0,
             'updated: ' + ', '.join(touched) if touched else 'already current'))


if __name__ == '__main__':
    main()
