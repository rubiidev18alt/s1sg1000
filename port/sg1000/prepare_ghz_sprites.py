#!/usr/bin/env python3
"""Prepare experimental Green Hill object sprites; not used by the ROM."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

from convert_tiles import TMS, distance, sms_colour
sys.path.insert(0, str(Path(__file__).resolve().parent / 'prototype'))
from menu_font import decode_hy

ROM_SHA256 = '6ad738965ece231427ee046b9905cfee470d5c01220afdd934da4673e4a2458b'
# Bank 1 addresses in annot/sonic1.cfg. The object renderer indexes 18 bytes
# per frame: 3 rows of 6 8x16 cells, terminated by FF at the start of a row.
OBJECTS = {'crabmeat': (0x66F9, 4), 'buzz_bomber': (0x6CF9, 6),
           'motobug': (0x6ECB, 4)}


def convert_tiles(tiles, palette):
    """Convert SMS 4bpp tiles to opaque single-colour TMS 8x8 masks."""
    if len(tiles) % 32 or len(palette) != 16:
        raise ValueError('expected complete 32-byte tiles and a 16-byte sprite palette')
    rgb = [sms_colour(c) for c in palette]
    costs = [[distance(c, target) for target in TMS[1:]] for c in rgb]
    patterns, colours = bytearray(), bytearray()
    for start in range(0, len(tiles), 32):
        rows = []
        counts = [0] * 16
        for y in range(8):
            planes = tiles[start + y * 4:start + y * 4 + 4]
            row = []
            for x in range(8):
                index = sum(((planes[p] >> (7 - x)) & 1) << p for p in range(4))
                counts[index] += 1
                row.append(index)
            rows.append(row)
        if sum(counts[1:]):
            colour = min(range(1, 16), key=lambda c: sum(
                counts[i] * costs[i][c - 1] for i in range(1, 16)))
        else:
            colour = 0
        colours.append(colour)
        for row in rows:
            value = 0
            for index in row:
                value = (value << 1) | (index != 0)
            patterns.append(value)
    return bytes(patterns), bytes(colours)


def read_frame_map(rom, offset, frame, tile_count):
    base = offset + frame * 18
    cells = []
    for row in range(3):
        start = base + row * 6
        if start + 6 > len(rom):
            raise ValueError('truncated SMS sprite map')
        if rom[start] == 0xFF:
            break
        for col, index in enumerate(rom[start:start + 6]):
            if index >= 0xFE:
                continue
            if index & 1 or index + 1 >= tile_count:
                raise ValueError('sprite map references unsupported tile pair')
            cells.append({'x': col * 8, 'y': row * 16,
                          'top_tile': index, 'bottom_tile': index + 1})
    return cells


def prepare(rom, compressed, palette, output):
    if hashlib.sha256(rom).hexdigest() != ROM_SHA256:
        raise ValueError('ROM does not match the supported SMS revision')
    if len(palette) != 32:
        raise ValueError('expected both 16-byte GHZ palettes')
    tiles = decode_hy(compressed)
    if len(tiles) != 128 * 32:
        raise ValueError('unexpected GHZ sprite-bank size')
    patterns, colours = convert_tiles(tiles, palette[16:])
    objects = {name: [read_frame_map(rom, offset, i, 128) for i in range(count)]
               for name, (offset, count) in OBJECTS.items()}
    manifest = {
        'source': 'lv_ghz.art2000', 'sms_vram_base': 8192,
        'tile_count': 128, 'tile_width': 8, 'tile_height': 8,
        'pattern_bytes_per_tile': 8, 'colour_bytes_per_tile': 1,
        'sms_sprite_palette': 1, 'transparent_source_index': 0,
        'objects': objects,
        'limitations': 'One TMS colour per tile. Sprite budgets, animation timing, collision and runtime integration are not implemented.'
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / 'patterns.bin').write_bytes(patterns)
    (output / 'colours.bin').write_bytes(colours)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, default=Path('baserom/sonic1.sms'))
    parser.add_argument('--data', type=Path, default=Path('src/data'))
    parser.add_argument('--output', type=Path, default=Path('build/sg1000/ghz_sprites'))
    args = parser.parse_args()
    try:
        manifest = prepare(args.rom.read_bytes(), (args.data / 'lv_ghz.art2000').read_bytes(),
                           (args.data / 'lv_ghz.pal3').read_bytes(), args.output)
    except (OSError, ValueError) as exc:
        parser.exit(1, 'error: {}\n'.format(exc))
    print('Prepared {} tiles and {} object maps in {}'.format(
        manifest['tile_count'], len(manifest['objects']), args.output))


if __name__ == '__main__':
    main()
