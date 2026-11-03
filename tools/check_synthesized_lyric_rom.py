"""Verify the glyph ROM inside TD's synthesized gate netlist.

Run after export_lyric_gate_netlist.tcl has produced
syn_1/lyric_gate_inspection.v (read-only inspection of the gate database).

The glyph table is delivered as four 8-bit slices so TD maps every slice to
8192x1 banks (a 32-bit array made TD use 1024x9 banks and drop the
uninitialised parity lane, losing 5190 bits). Because TD reorders the slices, the
word bit of each bank is taken from its own .doa() connection, and every stored
bit plane is compared row by row with the generated table.

TD packs the syllable case table into 512-deep block RAMs; count both data and
parity initialization bits. Sentence selection remains generated case logic.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
NETLIST = ROOT / 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/lyric_gate_inspection.v'
HDL = ROOT / 'proj/src/user_source/hdl_source'
GEOMETRY = re.compile(r'address_offset=(\d+);data_offset=(\d+);depth=(\d+);width=(\d+);')


def split_top(text):
    parts, depth, current = [], 0, ''
    for char in text:
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
        if char == ',' and depth == 0:
            parts.append(current)
            current = ''
            continue
        current += char
    if current.strip():
        parts.append(current)
    return parts


def output_map(segment):
    """Map each bank output bit to the glyph_table bit it carries, from .doa()."""
    match = re.search(r'\.doa\((.*?)\)\s*[,;]', segment, re.S)
    if not match:
        return {}
    body = match.group(1).strip()
    if body.startswith('{'):
        body = body[1:-1]
    result, bit = {}, 0
    for element in reversed(split_top(body)):
        found = re.search(r'font_row\s*\[(\d+)(?::(\d+))?\]', element)
        if found:
            high = int(found.group(1))
            low = int(found.group(2)) if found.group(2) else high
            for net in range(low, high + 1):
                result[bit] = net
                bit += 1
        else:
            bit += 1
    return result


def banks(text, prefix):
    found = []
    for match in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s*(\\\S+)\s*\(', text, re.S):
        params, name = match.groups()
        if not name.startswith('\\' + prefix):
            continue
        before = text[max(0, match.start() - 700):match.start()]
        shape = list(GEOMETRY.finditer(before))
        if not shape:
            raise AssertionError('Missing geometry for ' + name)
        initial = {int(index, 16): int(value, 16) for index, value in
                   re.findall(r'\.INIT_([0-9A-Fa-f]{2})\(256\'h([0-9A-Fa-f]+)\)', params)}
        if len(initial) != 32:
            raise AssertionError('Expected 32 init blocks for ' + name)
        found.append(dict(name=name, depth=int(shape[-1].group(3)), initial=initial,
                          map=output_map(text[match.end():match.end() + 1200])))
    return found


def main():
    text = NETLIST.read_text(encoding='utf-8', errors='replace')
    banks_all = banks(text, 'u_lyric_overlay/')
    if not banks_all:
        raise AssertionError('No lyric block RAM found')
    glyph_banks = [bank for bank in banks_all if bank['depth'] == 8192]
    event_banks = [bank for bank in banks_all if bank['depth'] == 512]
    if not glyph_banks:
        raise AssertionError('No glyph block RAM found')

    lanes = [[int(value, 16) for value in
              (HDL / ('lyric_font%d.hex' % lane)).read_text().split()] for lane in range(4)]
    glyph = [sum(lanes[lane][i] << (8 * lane) for lane in range(4))
             for i in range(len(lanes[0]))]

    stored = {}
    for bank in banks_all:
        for lane, net in bank['map'].items():
            if net in stored:
                raise AssertionError('glyph bit %d stored twice' % net)
            stored[net] = bank

    checked = 0
    for net in range(32):
        column = [(word >> net) & 1 for word in glyph]
        bank = stored.get(net)
        if bank is None:
            if any(column):
                raise AssertionError('glyph bit %d is used but not stored' % net)
            continue
        lane = [k for k, value in bank['map'].items() if value == net][0]
        for row, expected in enumerate(column):
            got = (bank['initial'][row // 256] >> (row % 256)) & 1
            if got != expected:
                raise AssertionError('glyph bit %d differs at row %d' % (net, row))
        checked += 1

    # Syllable table: TD packs the generated case back into 512x18 banks and puts
    # the 18th lane in the block parity bits (INITP_xx), so the data is complete.
    # Verified by total weight over data + parity blocks.
    song = json.loads((ROOT / 'material/board/timeline.json').read_text(encoding='utf-8'))
    packed = ([(event['glyph'] << 48) | (event['start'] << 24) | event['end']
               for event in song['events']])
    expected_ones = sum(bin(word).count('1') for word in packed)
    stored_ones = 0
    event_bank_names = {bank['name'] for bank in event_banks}
    for match in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s*(\\\S+)\s*\(', text, re.S):
        params, name = match.groups()
        # Synthesis renumbers muxes after unrelated case-table edits. Identify
        # the event banks by their recorded depth, not an unstable mux number.
        if name not in event_bank_names:
            continue
        stored_ones += sum(bin(int(value, 16)).count('1') for value in
                           re.findall(r'\.INITP?_[0-9A-Fa-f]{2}\(256\'h([0-9A-Fa-f]+)\)', params))
    if not event_banks:
        raise AssertionError('Syllable table is no longer a block RAM; update this check')
    if stored_ones != expected_ones:
        raise AssertionError('Syllable table holds %d set bits, expected %d'
                             % (stored_ones, expected_ones))
    print('PASS: %d glyph rows x %d stored bit planes match bit for bit; %d syllables keep '
          'exactly %d set bits in the packed banks (parity lane included); %d sentences are logic'
          % (len(glyph), checked, len(song['events']), stored_ones, len(song['lines'])))


if __name__ == '__main__':
    main()
