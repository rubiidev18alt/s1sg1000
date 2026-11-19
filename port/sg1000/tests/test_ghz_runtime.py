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

    def test_visual_rows_match_original_silhouette(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        data = rom.read_bytes()
        _, layout, flags, floor, _ = mod.prepare_ghz_layout.extract(data)
        encoded = mod.ghz_visual_rows(data)
        for y in range(64):
            pos = 128 + int.from_bytes(encoded[2*y:2*y+2], 'little')
            actual = []
            while len(actual) < 1024:
                count = int.from_bytes(encoded[pos:pos+2], 'little')
                actual.extend([encoded[pos+2]] * count)
                pos += 3
            expected = []
            for x in range(1024):
                kind = flags[layout[(y//4)*256 + x//4]] & 63
                value = floor[kind*32 + (x%4)*8 + 4]
                height = value if value < 128 else value - 256
                expected.append(int(value != 128 and (y%4)*8 + 4 >= height))
            self.assertEqual(actual, expected)


if __name__ == '__main__':
    unittest.main()
