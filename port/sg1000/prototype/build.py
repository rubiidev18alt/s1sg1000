#!/usr/bin/env python3
"""Build the Gearsystem SG-1000 physics experiment from the user's ROM."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'port/sg1000'))
import prepare_sonic
import layered_sonic
import menu_font
import prepare_ghz_layout
from itertools import groupby

# One floor height per 8-pixel column, on a 768x384 pixel test course.
HEIGHTS = ([208] * 12 + list(range(200, 136, -8)) + [144] * 10
           + list(range(152, 248, 8)) + [240] * 10
           + list(range(232, 152, -8)) + [160] * 10
           + list(range(168, 232, 8)) + [224] * 16)
WORLD_WIDTH = 96
WORLD_HEIGHT = 48



def ghz_runtime_data(rom):
    """RLE each row of collision types for random access on the Z80."""
    info, layout, flags, floor, _ = prepare_ghz_layout.extract(rom)
    assert (info['width_metatiles'], info['height_metatiles']) == (256, 16)
    rows = []
    for y in range(16):
        row = [flags[tile] & 0x3f for tile in layout[y * 256:(y + 1) * 256]]
        encoded = bytearray()
        for kind, group in groupby(row):
            count = sum(1 for _ in group)
            encoded.extend((count & 255, kind))  # 0 denotes 256
        rows.append(bytes(encoded))
    # 16 little-endian offsets relative to the start of the row data.
    offsets = bytearray()
    cursor = 0
    for row in rows:
        offsets.extend(cursor.to_bytes(2, 'little'))
        cursor += len(row)
    return bytes(offsets) + b''.join(rows), floor[:23 * 32]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--wla-z80', default='wla-z80')
    p.add_argument('--wlalink', default='wlalink')
    args = p.parse_args()
    data = ROOT / 'src/data'
    rom = ROOT / 'baserom/sonic1.sms'
    out = ROOT / 'build/sg1000/prototype'
    out.mkdir(parents=True, exist_ok=True)
    try:
        if not rom.exists():
            raise ValueError('put the supported SMS ROM at baserom/sonic1.sms')
        if not shutil.which(args.wla_z80) or not shutil.which(args.wlalink):
            raise ValueError('WLA-DX tools wla-z80 and wlalink are required')
        # Re-extract to validate the ROM and avoid stale/mismatched assets.
        data.mkdir(parents=True, exist_ok=True)
        subprocess.run([sys.executable, 'tools/rom_unpack.py', str(rom),
                        'annot/sonic1.cfg', 'src/whole.asm'], cwd=ROOT,
                       check=True, stdout=subprocess.DEVNULL)
        ghz_map, ghz_floor = ghz_runtime_data(rom.read_bytes())
        (out / 'ghz_collision_rows.bin').write_bytes(ghz_map)
        (out / 'ghz_floor_profiles.bin').write_bytes(ghz_floor)
        # Coarse monochrome silhouette, sampled at the centre of each 8x8 cell.
        tiles = bytearray()
        for kind in range(23):
            for y in range(4):
                for x in range(4):
                    value = ghz_floor[kind * 32 + x * 8 + 4]
                    height = value if value < 128 else value - 256
                    tiles.append(int(value != 128 and y * 8 + 4 >= height))
        (out / 'ghz_tiles.bin').write_bytes(tiles)
        (out / 'menu_font.bin').write_bytes(menu_font.font_patterns(
            (data / 'world_map_1_ending.art0000').read_bytes()))
        prepare_sonic.prepare(data, out / 'sonic')
        palette = (data / 'lv_ghz.pal3').read_bytes()[16:]
        frames = bytearray()
        for direction in ('r', 'l'):
            for index in range(0x2a):
                frame = (data / 'sonic_{:02X}_{}.sonicuncart'.format(index, direction)).read_bytes()
                patterns, colours = layered_sonic.convert(frame, palette)
                frames.extend(patterns + colours)
        (out / 'sonic_frames.bin').write_bytes(frames)
        assert len(HEIGHTS) == WORLD_WIDTH and all(h % 8 == 0 for h in HEIGHTS)
        (out / 'heights.bin').write_bytes(b''.join(h.to_bytes(2, 'little') for h in HEIGHTS))
        rows = [bytes(int(y * 8 >= HEIGHTS[x]) for x in range(WORLD_WIDTH))
                for y in range(WORLD_HEIGHT)]
        unique = list(dict.fromkeys(rows))
        (out / 'ground.bin').write_bytes(b''.join(unique))
        (out / 'ground_rows.bin').write_bytes(b''.join(
            (unique.index(row) * WORLD_WIDTH).to_bytes(2, 'little') for row in rows))
        subprocess.run([args.wla_z80, '-o', str(out / 'prototype.o'),
                        'port/sg1000/prototype/main.asm'], cwd=ROOT, check=True)
        (out / 'prototype.lnk').write_text('[objects]\n' + str(out / 'prototype.o') + '\n')
        (ROOT / 'out').mkdir(exist_ok=True)
        subprocess.run([args.wlalink, '-r', str(out / 'prototype.lnk'),
                        str(ROOT / 'out/sonic-physics.sg')], cwd=ROOT, check=True)
        print('Built out/sonic-physics.sg')
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        p.exit(1, 'build failed: {}\n'.format(exc))


if __name__ == '__main__':
    main()
