import importlib.util
from pathlib import Path
import unittest
import sys

ROOT = Path(__file__).resolve().parents[3]
path = ROOT / 'port/sg1000/prototype/build.py'
sys.path.insert(0, str(path.parent))
spec = importlib.util.spec_from_file_location('prototype_build', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class RuntimeLayoutTest(unittest.TestCase):
    def test_solid_connectivity_does_not_cross_air_or_diagonals(self):
        flags = bytes([0, 22, 16])
        layout = bytearray(4096)
        layout[256 + 1] = 1
        layout[256 + 2] = 2  # touching the solid block
        layout[2 * 256 + 3] = 2  # diagonal contact only
        layout[4 * 256 + 4] = 2  # isolated platform
        solid = mod.ghz_solid_cells(layout, flags)
        self.assertEqual(solid, {257, 258})

    def test_all_runtime_collision_types_and_profiles(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        rom_data = rom.read_bytes()
        _, layout, flags, floor, _ = mod.prepare_ghz_layout.extract(rom_data)
        encoded, profiles = mod.ghz_runtime_data(rom_data)
        self.assertEqual(profiles, floor[:23 * 32])
        solid = mod.ghz_solid_cells(layout, flags)
        self.assertIn(12 * 256 + 8, solid)  # starting terrain
        self.assertNotIn(9 * 256 + 28, solid)  # detached platform
        for y in range(16):
            index = 32 + int.from_bytes(encoded[y*2:y*2+2], 'little')
            row = []
            while len(row) < 256:
                count, kind = encoded[index:index+2]
                row.extend([kind] * (count or 256))
                index += 2
            self.assertEqual(row, [(flags[t] & 63) | (128 if y * 256 + x in solid else 0)
                                   for x, t in enumerate(layout[y*256:(y+1)*256])])
        self.assertLess(len(encoded) + len(profiles), 1400)

    def test_ramp_position_from_original_tile_specials(self):
        rom = ROOT / 'baserom/sonic1.sms'
        specials = ROOT / 'src/data/lv_ghz.tilespecials'
        if not rom.exists() or not specials.exists():
            self.skipTest('user-supplied ROM assets absent')
        self.assertEqual(mod.ghz_ramp_positions(rom.read_bytes(), specials.read_bytes()), [(2272, 416)])
        tilemap = (ROOT / 'src/data/lv_ghz.tilemap').read_bytes()[0x50 * 16:0x51 * 16]
        self.assertEqual({i for i, tile in enumerate(tilemap) if 0xd0 <= tile <= 0xd7},
                         {7, 8, 9, 11, 12, 13, 14, 15})
        with self.assertRaises(ValueError):
            mod.ghz_ramp_positions(rom.read_bytes(), bytes(2))

    def test_frame_deduplication_preserves_indices(self):
        frames = bytes([1] * 264 + [2] * 264 + [1] * 264)
        packed, offsets = mod.deduplicate_frames(frames)
        self.assertEqual(offsets, [0, 264, 0])
        self.assertEqual(len(packed), 528)
        self.assertEqual(b''.join(packed[i:i+264] for i in offsets), frames)
        with self.assertRaises(ValueError):
            mod.deduplicate_frames(bytes(265))

    def test_ring_buckets_cover_every_visible_position(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        rings, _, _ = mod.prepare_audio_rings.extract(rom.read_bytes())
        rings.sort()
        buckets = mod.ring_buckets(rings)
        for camera_x in range(0, 6337, 8):
            camera_page = camera_x // 256
            start = buckets[max(camera_page - 1, 0)]
            scan = [p for p in rings[start:] if p[0] // 256 <= camera_page + 2]
            visible = [p for p in rings if camera_x <= p[0] <= camera_x + 240]
            self.assertTrue(set(visible).issubset(scan), camera_x)
        with self.assertRaises(ValueError):
            mod.ring_buckets([(32, 0), (16, 0)])

    def test_ghz_terrain_patterns_use_original_art(self):
        art = ROOT / 'src/data/lv_ghz.art0000'
        if not art.exists():
            self.skipTest('unpacked SMS art absent')
        patterns = mod.ghz_terrain_patterns(art.read_bytes())
        self.assertEqual(len(patterns), 88)
        self.assertEqual(patterns[:8], bytes([0xff, 0xff, 0xaa, 0xaa, 0xaa, 0x44, 0x44, 0x44]))
        self.assertEqual(patterns[8:16], bytes(8))
        self.assertEqual(patterns[16:24], bytes([0xff] * 8))
        original = mod.menu_font.decode_hy(art.read_bytes())
        for index in range(8):
            source = original[(0xd0 + index) * 32:(0xd1 + index) * 32]
            mask = bytes(source[y] | source[y+1] | source[y+2] | source[y+3]
                         for y in range(0, 32, 4))
            self.assertEqual(patterns[24 + index * 8:32 + index * 8], mask)
        with self.assertRaises(ValueError):
            mod.ghz_terrain_patterns(b'')

    def test_visual_rows_match_original_silhouette(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        data = rom.read_bytes()
        _, layout, flags, floor, _ = mod.prepare_ghz_layout.extract(data)
        encoded = mod.ghz_visual_rows(data)
        previous = [0] * 1024
        for y in range(64):
            pos = 128 + int.from_bytes(encoded[2*y:2*y+2], 'little')
            actual = []
            ramp_tiles = {}
            while len(actual) < 1024:
                run = encoded[pos]
                pos += 1
                tile_type = run >> 6
                count = run & 31
                if run & 32:
                    count = (count << 8) | encoded[pos]
                    pos += 1
                self.assertIn(tile_type, (0, 1, 2, 3))
                self.assertGreater(count, 0)
                if tile_type == 3:
                    self.assertEqual(count, 1)
                    ramp_tiles[len(actual)] = encoded[pos]
                    pos += 1
                actual.extend([tile_type] * count)
            expected = []
            for x in range(1024):
                kind = flags[layout[(y//4)*256 + x//4]] & 63
                value = floor[kind*32 + (x%4)*8 + 4]
                height = value if value < 128 else value - 256
                expected.append(int(value != 128 and (y%4)*8 + 4 >= height))
            expected_tiles = [0 if not solid else (2 if not previous[x] else 1)
                              for x, solid in enumerate(expected)]
            ramp = {(287, 53), (284, 54), (285, 54), (287, 54),
                    (284, 55), (285, 55), (286, 55), (287, 55)}
            self.assertEqual(actual, [3 if (x, y) in ramp else tile
                                      for x, tile in enumerate(expected_tiles)])
            tilemap = data[0x10000 + 0x50 * 16:0x10000 + 0x51 * 16]
            self.assertEqual(ramp_tiles, {x: tilemap[(y - 52) * 4 + x - 284] - 0xd0
                                         for x, row in ramp if row == y})
            previous = expected


if __name__ == '__main__':
    unittest.main()
