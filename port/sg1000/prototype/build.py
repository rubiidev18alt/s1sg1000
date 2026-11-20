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
import prepare_audio_rings
import prepare_music
import struct
from itertools import groupby
from collections import deque

# One floor height per 8-pixel column, on a 768x384 pixel test course.
HEIGHTS = ([208] * 12 + list(range(200, 136, -8)) + [144] * 10
           + list(range(152, 248, 8)) + [240] * 10
           + list(range(232, 152, -8)) + [160] * 10
           + list(range(168, 232, 8)) + [224] * 16)
WORLD_WIDTH = 96
WORLD_HEIGHT = 48



def ghz_solid_cells(layout, flags):
    """Attach floor tiles connected to full-solid terrain; leave islands one-way.

    Original SMS profiles encode direction, not a separate material bit. For
    this test level, connected terrain is solid while detached platforms stay
    semisolid. Connectivity is four-way to avoid bridging diagonal gaps.
    """
    kinds = [flags[tile] & 0x3f for tile in layout]
    solid = {i for i, kind in enumerate(kinds) if kind == 22}
    queue = deque(solid)
    while queue:
        i = queue.popleft()
        x, y = i % 256, i // 256
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < 256 and 0 <= ny < 16:
                j = ny * 256 + nx
                if kinds[j] and j not in solid:
                    solid.add(j)
                    queue.append(j)
    return solid


def ghz_ramp_positions(rom, specials):
    """Locate SMS ramp-jump metatiles (special action 02) in GHZ1."""
    _, layout, _, _, _ = prepare_ghz_layout.extract(rom)
    if max(layout) >= len(specials):
        raise ValueError('truncated GHZ tile-special table')
    return [(i % 256 * 32, i // 256 * 32)
            for i, tile in enumerate(layout) if specials[tile] == 2]


def ghz_runtime_data(rom):
    """RLE each row of collision types for random access on the Z80."""
    info, layout, flags, floor, _ = prepare_ghz_layout.extract(rom)
    assert (info['width_metatiles'], info['height_metatiles']) == (256, 16)
    rows = []
    solid = ghz_solid_cells(layout, flags)
    for y in range(16):
        row = [(flags[tile] & 0x3f) | (0x80 if y * 256 + x in solid else 0)
               for x, tile in enumerate(layout[y * 256:(y + 1) * 256])]
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


def ghz_terrain_patterns(art):
    """Reduce original SMS grass/soil tiles to two TMS Graphics I colours.

    Tile 01 contains GHZ grass; tiles 02/03 are the two solid colours in
    the original checkerboard. A tile gets one fixed colour pair.
    """
    raw = menu_font.decode_hy(art)
    if len(raw) < 0xd8 * 32:
        raise ValueError('truncated GHZ art')
    def convert(index, bright):
        result = bytearray()
        for y in range(8):
            planes = raw[index * 32 + y * 4:index * 32 + y * 4 + 4]
            row = 0
            for x in range(8):
                colour = sum(((planes[p] >> (7 - x)) & 1) << p for p in range(4))
                row |= (colour in bright) << (7 - x)
            result.append(row)
        return bytes(result)
    grass = convert(0x01, {5, 6})
    # The SMS highlight and shadow use extra colours. Keep a clean light-green
    # lip and the original grass texture below it in the two-colour version.
    grass = bytes([0xff, 0xff]) + grass[2:]
    # Original GHZ d0..d7 ramp tiles, preserving their tile-specific shapes.
    # Graphics I keeps the original opacity as one bit, not the SMS colours.
    return (grass + convert(0x02, {3}) + convert(0x03, {3})
            + b''.join(convert(index, set(range(1, 16)))
                       for index in range(0xd0, 0xd8)))


# SMS signpost sprite maps (8x16 pieces), in the same order as the original
# unspun, three spin views, and the no-bonus result. FE/FF cells are blank.
SIGNPOST_MAPS = (
    (0x4e, 0x50, 0x52, 0x54, 0x6e, 0x70, 0x72, 0x74, None, 0x42, 0x44, None),
    (0x16, 0x18, 0x1a, 0x1c, 0x36, 0x38, 0x3a, 0x3c, None, 0x42, 0x44, None),
    (None, 0x12, 0x14, None, None, 0x32, 0x34, None, None, 0x42, 0x44, None),
    (0x56, 0x58, 0x5a, 0x5c, 0x76, 0x78, 0x7a, 0x7c, None, 0x42, 0x44, None),
    (0x00, 0x02, 0x04, 0x06, 0x20, 0x22, 0x24, 0x26, None, 0x42, 0x44, None),
)

def ghz_signpost(objects):
    """Read the original object list, excluding the implicit Sonic entry."""
    if not objects or len(objects) != 1 + (objects[0] - 1) * 3:
        raise ValueError('invalid GHZ1 object list')
    positions = [(objects[i+1] * 32, objects[i+2] * 32)
                 for i in range(1, len(objects), 3) if objects[i] == 7]
    if len(positions) != 1:
        raise ValueError('unexpected number of GHZ1 signposts')
    return positions[0]


# Pattern slots grouped by Graphics I colour: grey/cyan, yellow/cyan,
# red/yellow. Each entry is a row/column in the original 4x6 tile map;
# unused slots are blank to keep each colour group aligned to eight tiles.
SIGNPOST_SLOTS = (
    (1, 0), (1, 3), (4, 1), (4, 2), (5, 1), (5, 2), None, None,
    (2, 0), (2, 3), (3, 0), (3, 3), None, None, None, None,
    (1, 1), (1, 2), (2, 1), (2, 2), (3, 1), (3, 2), None, None,
)

def signpost_patterns(art):
    """Convert original signpost frames into three TMS colour groups.

    Border/pole use grey against sky, side pieces yellow against sky, and
    interior details red against yellow. The narrow side-on view changes its
    interior group to grey/sky at runtime, preserving its transparent gaps.
    """
    raw = menu_font.decode_hy(art)
    if len(raw) < 128 * 32:
        raise ValueError('truncated signpost art')
    out = bytearray()
    for frame, mapping in enumerate(SIGNPOST_MAPS):
        for slot, cell in enumerate(SIGNPOST_SLOTS):
            if cell is None:
                out.extend(bytes(8))
                continue
            row, col = cell
            tile = mapping[(row // 2) * 4 + col]
            if tile is None:
                out.extend(bytes(8))
                continue
            tile += row % 2
            for y in range(8):
                planes = raw[tile * 32 + y * 4:tile * 32 + y * 4 + 4]
                if slot < 16 or frame == 2:
                    # Opaque silhouette against cyan, including SMS colour 8.
                    out.append(planes[0] | planes[1] | planes[2] | planes[3])
                else:
                    # Red/black/brown/blue marks contrast with the yellow face;
                    # grey and white join yellow under the two-colour limit.
                    bits = 0
                    for x in range(8):
                        colour = sum(((planes[p] >> (7-x)) & 1) << p for p in range(4))
                        if colour not in (0, 5, 7, 9):
                            bits |= 0x80 >> x
                    out.append(bits)
    return bytes(out)


def ghz_scenery(x, y):
    """Small repeating cloud and island/water tiles, in empty GHZ sky only."""
    phase = x % 64
    if y in (30, 38, 46) and phase in (12, 13):
        return 112 + phase - 12
    if y in (34, 42, 50) and phase in (40, 41):
        return 114 + phase - 40
    if y in (35, 43, 51) and phase in (40, 41):
        return 116 + phase - 40
    return None


def ghz_visual_rows(rom):
    """Pack collision silhouettes with surface/soil into short/long RLE runs.

    The two high bits select sky, soil, grass or the ramp artwork. Collision
    is unchanged; grass marks occupied cells with an empty cell directly above.
    """
    _, layout, flags, floor, _ = prepare_ghz_layout.extract(rom)
    solid = []
    for y in range(64):
        cells = []
        for x in range(1024):
            kind = flags[layout[(y // 4) * 256 + x // 4]] & 63
            value = floor[kind * 32 + (x % 4) * 8 + 4]
            height = value if value < 128 else value - 256
            cells.append(int(value != 128 and (y % 4) * 8 + 4 >= height))
        solid.append(cells)
    ramp_tilemap = rom[0x10000 + 0x50 * 16:0x10000 + 0x51 * 16]
    if len(ramp_tilemap) != 16:
        raise ValueError('truncated GHZ ramp tilemap')
    rows = []
    for y, cells in enumerate(solid):
        types = [0 if not value else (2 if y == 0 or not solid[y - 1][x] else 1)
                 for x, value in enumerate(cells)]
        scenery = {}
        for x, tile_type in enumerate(types):
            tile = ghz_scenery(x, y)
            if tile_type == 0 and tile is not None:
                types[x] = 3
                scenery[x] = tile
        # The original special-02 ramp's nonempty 8x8 cells, derived from
        # metatile $50 at (2272,416). Collision remains unchanged.
        for xoffset, yoffset in ((3, 1), (0, 2), (1, 2), (3, 2),
                                 (0, 3), (1, 3), (2, 3), (3, 3)):
            if y == 416 // 8 + yoffset:
                types[2272 // 8 + xoffset] = 3
        packed = bytearray()
        x = 0
        for value, group in groupby(types):
            count = sum(1 for _ in group)
            if value == 3:
                # The fourth visual type has one extra byte per cell, giving
                # its exact SMS ramp tile; split runs to retain tile identity.
                for column in range(x, x + count):
                    if column in scenery:
                        tile_index = scenery[column] - 80
                    else:
                        index = (y - 52) * 4 + column - 284
                        tile = ramp_tilemap[index]
                        if not 0xd0 <= tile <= 0xd7:
                            raise ValueError('unexpected GHZ ramp tile')
                        tile_index = tile - 0xd0
                    packed.extend((0xc1, tile_index))
            elif count <= 31:
                packed.append(value << 6 | count)
            else:
                packed.extend((value << 6 | 0x20 | count >> 8, count & 255))
            x += count
        rows.append(bytes(packed))
    offsets = bytearray()
    cursor = 0
    for row in rows:
        offsets.extend(cursor.to_bytes(2, 'little'))
        cursor += len(row)
    return bytes(offsets) + b''.join(rows)


def deduplicate_frames(frames, frame_size=264):
    """Store repeated whole frames once while preserving the pointer order."""
    if not frames or len(frames) % frame_size:
        raise ValueError('incomplete sprite frame data')
    unique = []
    offsets = []
    lookup = {}
    for i in range(0, len(frames), frame_size):
        frame = bytes(frames[i:i + frame_size])
        if frame not in lookup:
            lookup[frame] = len(unique) * frame_size
            unique.append(frame)
        offsets.append(lookup[frame])
    return b''.join(unique), offsets


def ring_buckets(rings):
    """Index sorted GHZ rings by 256-pixel page for bounded runtime scans."""
    if len(rings) > 255 or rings != sorted(rings):
        raise ValueError('ring positions must be sorted and fit in one byte')
    return bytes(next((i for i, (x, _) in enumerate(rings) if x >= page * 256), len(rings))
                 for page in range(32))


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
        rom_bytes = rom.read_bytes()
        ghz_rings, songs, _ = prepare_audio_rings.extract(rom_bytes)
        (out / 'music_score.inc').write_text(prepare_music.compile_score(songs))
        ghz_rings.sort()
        (out / 'ghz_ring_buckets.bin').write_bytes(ring_buckets(ghz_rings))
        test_rings = [(96, 176), (112, 176), (160, 104), (352, 208)]
        for name, rings in [('ghz', ghz_rings), ('test', test_rings)]:
            (out / (name + '_rings.bin')).write_bytes(
                b''.join(struct.pack('<HH', x, y) for x, y in rings))
        ring_patterns, hud_patterns = prepare_audio_rings.ring_and_hud_art(rom_bytes)
        (out / 'ring_patterns.bin').write_bytes(ring_patterns)
        (out / 'ring_hud_patterns.bin').write_bytes(hud_patterns)
        ramps = ghz_ramp_positions(rom_bytes, (data / 'lv_ghz.tilespecials').read_bytes())
        if ramps != [(2272, 416)]:
            raise ValueError('unexpected GHZ1 launch-ramp layout')
        sign = ghz_signpost((data / 'lv_ghz_1.objects').read_bytes())
        if sign != (6432, 384):
            raise ValueError('unexpected GHZ1 signpost location')
        (out / 'signpost_patterns.bin').write_bytes(
            signpost_patterns((data / 'signpost.art2000').read_bytes()))
        (out / 'ghz_ramp.inc').write_text(
            '.DEFINE GHZ_RAMP_X {}\n.DEFINE GHZ_RAMP_Y {}\n'.format(*ramps[0]))
        ghz_map, ghz_floor = ghz_runtime_data(rom_bytes)
        (out / 'ghz_collision_rows.bin').write_bytes(ghz_map)
        (out / 'ghz_floor_profiles.bin').write_bytes(ghz_floor)
        (out / 'ghz_visual_rows.bin').write_bytes(ghz_visual_rows(rom_bytes))
        (out / 'ghz_terrain_patterns.bin').write_bytes(
            ghz_terrain_patterns((data / 'lv_ghz.art0000').read_bytes()))
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
        frame_data, frame_offsets = deduplicate_frames(frames)
        (out / 'sonic_frames.bin').write_bytes(frame_data)
        (out / 'sonic_frame_ptrs.inc').write_text(
            ''.join('.dw frame_data + {}\n'.format(offset) for offset in frame_offsets))
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
