#!/usr/bin/env python3
"""Convert unpacked SMS background tiles to TMS9918A Graphics II rows.

This is a lossy conversion: the TMS9918A permits only two colours per
8-pixel character row. It does not convert SMS sprites or tile maps.
"""
import argparse
from pathlib import Path

# Nominal TMS9918A palette, excluding colour 0 (transparent/backdrop).
TMS = (
    None, (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
)


def sms_colour(value):
    """SMS CRAM uses BBGGRR, two bits per channel."""
    return ((value & 3) * 85, ((value >> 2) & 3) * 85,
            ((value >> 4) & 3) * 85)


def distance(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def convert(tiles, palette):
    if len(tiles) % 32:
        raise ValueError('SMS tile data must be a multiple of 32 bytes')
    if len(palette) != 16:
        raise ValueError('SMS palette must contain exactly 16 CRAM bytes')
    rgb = [sms_colour(c) for c in palette]
    # Precompute distances: each row only has eight pixels but 120 pairs.
    distances = [[distance(colour, target) for target in TMS[1:]] for colour in rgb]
    patterns, colours = bytearray(), bytearray()
    for tile_start in range(0, len(tiles), 32):
        for row in range(8):
            planes = tiles[tile_start + row * 4:tile_start + row * 4 + 4]
            pixels = [sum(((planes[p] >> bit) & 1) << p for p in range(4))
                      for bit in range(7, -1, -1)]
            # The first best pair wins ties, making conversion deterministic.
            best = min((sum(min(distances[p][lo - 1], distances[p][hi - 1])
                            for p in pixels), lo, hi)
                       for lo in range(1, 16) for hi in range(lo, 16))
            _, lo, hi = best
            pattern = 0
            for pixel in pixels:
                pattern = (pattern << 1) | (distances[pixel][hi - 1] < distances[pixel][lo - 1])
            patterns.append(pattern)
            colours.append((hi << 4) | lo)
    return bytes(patterns), bytes(colours)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tiles', type=Path, help='uncompressed SMS 4bpp tile data')
    parser.add_argument('palette', type=Path, help='16 raw SMS CRAM palette bytes')
    parser.add_argument('patterns', type=Path, help='output Graphics II pattern bytes')
    parser.add_argument('colours', type=Path, help='output Graphics II colour bytes')
    args = parser.parse_args()
    try:
        patterns, colours = convert(args.tiles.read_bytes(), args.palette.read_bytes())
        if args.patterns.resolve() == args.colours.resolve():
            parser.error('pattern and colour outputs must be different files')
        args.patterns.write_bytes(patterns)
        args.colours.write_bytes(colours)
    except (ValueError, OSError) as exc:
        parser.exit(1, 'error: {}\n'.format(exc))


if __name__ == '__main__':
    main()
