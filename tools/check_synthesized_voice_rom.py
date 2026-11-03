"""Compare TD's inferred initialized bit-plane BRAMs to the source voice ROM."""
import re
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NETLIST = ROOT / 'proj/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/voice_gate_inspection.v'
HEX = ROOT / 'proj/src/user_source/hdl_source/rom/voice_test.hex'


def main():
    metadata = json.loads((ROOT / 'material/test_voice/metadata.json').read_text(encoding='utf-8'))
    rtl = (ROOT / 'proj/src/user_source/hdl_source/voice_rom_player.v').read_text(encoding='utf-8')
    for voice in metadata['voices']:
        index = voice['photo_id']
        length = int(re.search(rf'parameter integer LENGTH{index}\s*=\s*(\d+)', rtl).group(1))
        if length != voice['samples']:
            raise AssertionError(f'LENGTH{index} differs from generated voice metadata; update RTL and rebuild')
    text = NETLIST.read_text(encoding='utf-8')
    source = [int(word, 16) for word in HEX.read_text().split()]
    reconstructed = [0] * len(source)
    banks = 0
    for match in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s*(\\\S+)\s*\(', text, re.S):
        params, name = match.groups()
        if not name.startswith('\\u_voice_rom_player/'):
            continue
        comments = text[max(0, match.start() - 600):match.start()]
        shape = list(re.finditer(r'address_offset=(\d+);data_offset=(\d+);depth=(\d+);width=(\d+);', comments))
        if not shape:
            raise AssertionError(f'Missing geometry for {name}')
        offset, bit, depth, width = map(int, shape[-1].groups())
        if width != 1 or depth != 8192:
            raise AssertionError(f'Unexpected voice BRAM geometry: {name}')
        initial = dict((int(index, 16), int(value, 16)) for index, value in
                       re.findall(r'\.INIT_([0-9A-Fa-f]{2})\(256\x27h([0-9A-Fa-f]+)\)', params))
        if len(initial) != 32:
            raise AssertionError(f'Expected 32 initialization blocks for {name}')
        for address in range(depth):
            value = (initial[address // 256] >> (address % 256)) & 1
            reconstructed[offset + address] |= value << bit
        banks += 1
    if banks != 32:
        raise AssertionError(f'Expected 32 voice BRAM banks, found {banks}')
    mismatches = [i for i, (a, b) in enumerate(zip(source, reconstructed)) if a != b]
    if mismatches:
        raise AssertionError(f'Voice initialization mismatch at {len(mismatches)} addresses; first={mismatches[0]}')
    print(f'PASS: synthesized ROM contains all {len(source)} voice bytes in {banks} initialized BRAM banks')


if __name__ == '__main__':
    main()
