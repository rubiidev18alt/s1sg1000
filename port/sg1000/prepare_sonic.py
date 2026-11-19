#!/usr/bin/env python3
"""Convert all extracted Sonic frames for the SG-1000 graphics experiment."""
import argparse
from pathlib import Path

from convert_sonic import convert


def prepare(data_dir, output_dir):
    # .pal3 contains both 16-byte SMS palettes; Sonic uses palette 1.
    palette = (data_dir / 'lv_ghz.pal3').read_bytes()
    if len(palette) != 32:
        raise ValueError('lv_ghz.pal3 must contain both 16-byte SMS palettes')
    frames = []
    # Source order is numbered separately for each facing direction.
    for direction in ('r', 'l'):
        for index in range(0x2a):
            filename = 'sonic_{:02X}_{}.sonicuncart'.format(index, direction)
            path = data_dir / filename
            patterns, colours = convert(path.read_bytes(), palette[16:])
            frames.append((direction, index, patterns, colours))
    output_dir.mkdir(parents=True, exist_ok=True)
    for direction, index, patterns, colours in frames:
        prefix = output_dir / 'sonic_{:02x}_{}'.format(index, direction)
        prefix.with_suffix('.patterns').write_bytes(patterns)
        prefix.with_suffix('.colours').write_bytes(colours)
    return len(frames)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, default=Path('src/data'))
    parser.add_argument('--output', type=Path, default=Path('build/sg1000/sonic'))
    args = parser.parse_args()
    try:
        count = prepare(args.data, args.output)
    except (OSError, ValueError) as exc:
        parser.exit(1, 'error: {}\n'.format(exc))
    print('Converted {} frames to {}'.format(count, args.output))


if __name__ == '__main__':
    main()
