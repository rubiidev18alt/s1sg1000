#!/usr/bin/env python3
"""Convert an extracted Sonic 3bpp art frame to TMS9918 8x8 sprites."""
import argparse
from pathlib import Path

from convert_tiles import TMS, distance, sms_colour


def convert(frame, palette):
    """Return 12 patterns and their colours in the original source tile order.

    Pixel index zero is transparent. Each nonempty 8x8 pattern is opaque in
    the best single TMS colour for all its nonzero pixels. Empty tiles use
    colour 0. Placement and animation must be supplied separately.
    """
    if len(frame) != 288:
        raise ValueError('Sonic frame must be exactly 288 bytes (12 3bpp tiles)')
    if len(palette) != 16:
        raise ValueError('SMS sprite palette must contain exactly 16 bytes')
    rgb = [sms_colour(c) for c in palette]
    patterns, colours = bytearray(), bytearray()
    for tile in range(12):
        indices = []
        for row in range(8):
            start = tile * 24 + row * 3
            planes = frame[start:start + 3]
            indices.append([sum(((planes[p] >> bit) & 1) << p for p in range(3))
                            for bit in range(7, -1, -1)])
        opaque = [p for row in indices for p in row if p != 0]
        if opaque:
            colour = min(range(1, 16),
                         key=lambda c: sum(distance(rgb[p], TMS[c]) for p in opaque))
        else:
            colour = 0
        colours.append(colour)
        for row in indices:
            mask = 0
            for pixel in row:
                mask = (mask << 1) | (pixel != 0)
            patterns.append(mask)
    return bytes(patterns), bytes(colours)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frame', type=Path, help='288-byte extracted .sonicuncart frame')
    parser.add_argument('palette', type=Path, help='16-byte SMS sprite palette')
    parser.add_argument('patterns', type=Path, help='output 96 sprite pattern bytes')
    parser.add_argument('colours', type=Path, help='output 12 sprite colour bytes')
    args = parser.parse_args()
    try:
        if args.patterns.resolve() == args.colours.resolve():
            parser.error('outputs must be different files')
        patterns, colours = convert(args.frame.read_bytes(), args.palette.read_bytes())
        args.patterns.write_bytes(patterns)
        args.colours.write_bytes(colours)
    except (OSError, ValueError) as exc:
        parser.exit(1, 'error: {}\n'.format(exc))


if __name__ == '__main__':
    main()
