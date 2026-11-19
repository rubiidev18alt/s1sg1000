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
    def test_all_runtime_collision_types_and_profiles(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        rom_data = rom.read_bytes()
        _, layout, flags, floor, _ = mod.prepare_ghz_layout.extract(rom_data)
        encoded, profiles = mod.ghz_runtime_data(rom_data)
        self.assertEqual(profiles, floor[:23 * 32])
        for y in range(16):
            index = 32 + int.from_bytes(encoded[y*2:y*2+2], 'little')
            row = []
            while len(row) < 256:
                count, kind = encoded[index:index+2]
                row.extend([kind] * (count or 256))
                index += 2
            self.assertEqual(row, [flags[t] & 63 for t in layout[y*256:(y+1)*256]])
        self.assertLess(len(encoded) + len(profiles), 1400)


if __name__ == '__main__':
    unittest.main()
