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

# One floor height per 8-pixel column, on a 768x384 pixel test course.
HEIGHTS = ([208] * 12 + list(range(200, 136, -8)) + [144] * 10
           + list(range(152, 248, 8)) + [240] * 10
           + list(range(232, 152, -8)) + [160] * 10
           + list(range(168, 232, 8)) + [224] * 16)
WORLD_WIDTH = 96
WORLD_HEIGHT = 48



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
        (out / 'ground.bin').write_bytes(bytes(
            1 if y * 8 >= HEIGHTS[x] else 0
            for y in range(WORLD_HEIGHT) for x in range(WORLD_WIDTH)))
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
