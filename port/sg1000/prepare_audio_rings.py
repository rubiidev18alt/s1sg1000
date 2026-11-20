#!/usr/bin/env python3
"""Extract GHZ1 ring positions and original SMS PSG streams for porting.

This produces preparation data only; it does not add a music or ring runtime.
"""
import argparse
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'prototype'))
import menu_font
import prepare_ghz_layout

# Bank 3's CPU $4000-$7fff window starts at file offset $c000.
COMMON_HUD_ART = (0x2F92E, 0x3C2)
RING_ART = (0x2FCF0, 0x300)  # six frames, 4 SMS tiles per frame

SONGS = {
    'title': (0xE4C3, 0x179),
    'ghz': (0xC7D0, 0x53A),
    'clear': (0xE8B4, 0xDD),
}


def ghz_rings(layout, width=256, height=16):
    """Return 16x16 ring top-lefts in SMS layout order.

    The original collision routine checks a metatile ID masked with $7f for
    values >=$79, then tests bits 0/1 for a ring in each 16px half. The
    corresponding replacement graphic begins 8px down from the metatile top.
    """
    if width <= 0 or height <= 0 or len(layout) != width * height:
        raise ValueError('invalid layout dimensions')
    rings = []
    for i, tile in enumerate(layout):
        if tile & 0x7f < 0x79:
            continue
        for half in range(2):
            if tile & (1 << half):
                rings.append(((i % width) * 32 + half * 16,
                              (i // width) * 32 + 8))
    return rings


def song_streams(rom, name):
    """Read the song header's four little-endian, song-relative offsets."""
    start, size = SONGS[name]
    song = prepare_ghz_layout.slice_exact(rom, start, size)
    if len(song) < 10:
        raise ValueError('truncated song header')
    offsets = struct.unpack_from('<4H', song)
    if any(offset < 10 or offset >= len(song) for offset in offsets):
        raise ValueError('invalid song channel offset')
    return song, offsets


def opaque_patterns(planar):
    """Convert SMS planar 4bpp tiles to transparent/opaque TMS patterns."""
    if len(planar) % 32:
        raise ValueError('incomplete SMS art tile')
    out = bytearray()
    for row in range(0, len(planar), 4):
        out.append(planar[row] | planar[row + 1] | planar[row + 2] | planar[row + 3])
    return bytes(out)


def ring_and_hud_art(rom):
    # SMS HUD sprite IDs $80-$92 are digits 0..9, two 8x8 tiles each;
    # $A6/$A8 are the two 8x16 halves of the ring emblem. The common art
    # loads at the corresponding sprite tile $80, so subtract $80.
    source = prepare_ghz_layout.slice_exact(rom, *COMMON_HUD_ART)
    hud = menu_font.decode_hy(source)
    indices = list(range(20)) + [38, 39, 40, 41]
    if len(hud) < (max(indices) + 1) * 32:
        raise ValueError('truncated HUD art')
    hud_patterns = opaque_patterns(b''.join(hud[i*32:(i+1)*32] for i in indices))
    ring_patterns = opaque_patterns(prepare_ghz_layout.slice_exact(rom, *RING_ART))
    return ring_patterns, hud_patterns


def extract(rom):
    metadata, layout, _, _, _ = prepare_ghz_layout.extract(rom)
    rings = ghz_rings(layout, metadata['width_metatiles'], metadata['height_metatiles'])
    songs = {}
    info = {}
    for name in SONGS:
        data, offsets = song_streams(rom, name)
        songs[name] = data
        info[name] = {'rom_offset': SONGS[name][0], 'byte_length': len(data),
                      'channel_offsets': list(offsets)}
    return rings, songs, info


def prepare(rom, out):
    rings, songs, info = extract(rom)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'ghz1_rings.bin').write_bytes(b''.join(struct.pack('<HH', x, y) for x, y in rings))
    for name, song in songs.items():
        (out / (name + '.song')).write_bytes(song)
    ring_art, hud_art = ring_and_hud_art(rom)
    (out / 'ring_patterns.bin').write_bytes(ring_art)
    (out / 'hud_patterns.bin').write_bytes(hud_art)
    manifest = {'ghz1_ring_count': len(rings), 'ring_record_format': 'little-endian u16 x, u16 y',
                'ring_position': 'top-left of the 16x16 SMS ring graphic',
                'rings_order': 'layout row-major, left half before right',
                'ring_pattern_format': '6 frames of 4 tile-major monochrome 8x8 patterns',
                'hud_pattern_format': '20 digit tiles followed by 4 ring-emblem tiles',
                'songs': info, 'status': 'preparation only; no SG-1000 runtime yet'}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, default=Path('baserom/sonic1.sms'))
    parser.add_argument('--output', type=Path, default=Path('build/sg1000/audio_rings'))
    args = parser.parse_args()
    try:
        manifest = prepare(args.rom.read_bytes(), args.output)
    except (OSError, ValueError, struct.error) as exc:
        parser.exit(1, 'error: {}\n'.format(exc))
    print('Prepared {} GHZ1 rings and two SMS song streams in {}'.format(
        manifest['ghz1_ring_count'], args.output))


if __name__ == '__main__':
    main()
