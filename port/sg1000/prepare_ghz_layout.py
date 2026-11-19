#!/usr/bin/env python3
"""Extract the original GHZ1 layout and collision profiles from the SMS ROM.

The output is preparation data, not a playable SG-1000 level.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROM_SHA256 = '6ad738965ece231427ee046b9905cfee470d5c01220afdd934da4673e4a2458b'
LEVEL_HEADERS = 0x15580
LAYOUT_BASE = 0x14000
TILEFLAGS_POINTERS = 0x3A65
PUSH_UP_POINTERS = 0x448A
PUSH_DOWN_POINTERS = 0x41EC
PHYSICS_TYPES = 47
GHZ_TILEFLAGS_LENGTH = 184


def u16(data, offset):
    if offset < 0 or offset + 2 > len(data):
        raise ValueError('pointer outside ROM')
    return struct.unpack_from('<H', data, offset)[0]


def slice_exact(data, start, length):
    if start < 0 or length < 0 or start + length > len(data):
        raise ValueError('data outside ROM')
    return data[start:start + length]


def decode_layout(data, expected_size):
    # SMS layout RLE: a repeated literal triggers an extra repeat count;
    # zero represents 256 extra copies. The first literal already appeared.
    out = bytearray()
    previous = None
    pos = 0
    while pos < len(data):
        value = data[pos]
        pos += 1
        if value != previous:
            out.append(value)
            previous = value
        else:
            if pos >= len(data):
                raise ValueError('truncated layout run')
            repeats = data[pos] or 256
            pos += 1
            if len(out) + repeats > expected_size:
                raise ValueError('layout run exceeds output size')
            out.extend(bytes([value]) * repeats)
            previous = None
        if len(out) > expected_size:
            raise ValueError('layout exceeds output size')
    if len(out) != expected_size:
        raise ValueError('layout has incorrect output size')
    return bytes(out)


def physics_tables(rom, pointer_table):
    return bytes(value for kind in range(PHYSICS_TYPES)
                 for value in slice_exact(rom, u16(rom, pointer_table + kind * 2), 32))


def extract(rom):
    if hashlib.sha256(rom).hexdigest() != ROM_SHA256:
        raise ValueError('ROM does not match the supported Sonic 1 SMS revision')
    header = LEVEL_HEADERS + u16(rom, LEVEL_HEADERS)
    width, height, x0, x1, y0, y1 = struct.unpack_from('<6H', rom, header + 1)
    spawn_x, spawn_y = rom[header + 13:header + 15]
    address = LAYOUT_BASE + u16(rom, header + 15)
    size = u16(rom, header + 17)
    layout = decode_layout(slice_exact(rom, address, size), width * height)
    flag_addr = u16(rom, TILEFLAGS_POINTERS + 2 * rom[header])
    flags = slice_exact(rom, flag_addr, GHZ_TILEFLAGS_LENGTH)
    if max(layout) >= len(flags):
        raise ValueError('layout contains an unknown metatile')
    up = physics_tables(rom, PUSH_UP_POINTERS)
    down = physics_tables(rom, PUSH_DOWN_POINTERS)
    # Read the pixel-accurate 32-column floor and ceiling profiles unchanged.
    # $80 is no surface; other bytes are signed pixel offsets from metatile top.
    metadata = {'width_metatiles': width, 'height_metatiles': height,
                'metatile_pixels': 32, 'width_pixels': width * 32,
                'height_pixels': height * 32, 'spawn_x_pixels': spawn_x * 32,
                'spawn_y_pixels': spawn_y * 32,
                'original_camera_limits': {'x0': x0, 'x1': x1, 'y0': y0, 'y1': y1},
                'layout_rom_offset': address, 'layout_compressed_bytes': size,
                'layout_order': 'row-major 32x32 metatile IDs',
                'physics_profile_count': PHYSICS_TYPES,
                'profile_encoding': 'signed 8-bit y offset; 0x80 = no collision',
                'status': 'data only; SG-1000 rendering and collision not yet implemented'}
    return metadata, layout, flags, up, down


def prepare(rom, output):
    metadata, layout, flags, up, down = extract(rom)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'layout.bin').write_bytes(layout)
    (output / 'tileflags.bin').write_bytes(flags)
    (output / 'floor_profiles.bin').write_bytes(up)
    (output / 'ceiling_profiles.bin').write_bytes(down)
    (output / 'manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, default=Path('baserom/sonic1.sms'))
    parser.add_argument('--output', type=Path, default=Path('build/sg1000/ghz1_layout'))
    args = parser.parse_args()
    try:
        metadata = prepare(args.rom.read_bytes(), args.output)
    except (OSError, ValueError, struct.error) as exc:
        parser.exit(1, 'error: {}\n'.format(exc))
    print('Extracted GHZ1 {}x{} pixels to {}'.format(
        metadata['width_pixels'], metadata['height_pixels'], args.output))


if __name__ == '__main__':
    main()
