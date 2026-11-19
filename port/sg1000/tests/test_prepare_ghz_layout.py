import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('ghz_layout', ROOT / 'port/sg1000/prepare_ghz_layout.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class LayoutTests(unittest.TestCase):
    def test_runs_and_wraparound(self):
        self.assertEqual(mod.decode_layout(bytes([1, 1, 3, 2]), 5), bytes([1] * 4 + [2]))
        self.assertEqual(mod.decode_layout(bytes([7, 7, 0]), 257), bytes([7] * 257))

    def test_reject_bad_runs_and_sizes(self):
        for data, size in [(bytes([1, 1]), 2), (bytes([1, 1, 4]), 3), (bytes([1]), 2)]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                mod.decode_layout(data, size)

    def test_original_rom(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        info, layout, flags, up, down = mod.extract(rom.read_bytes())
        self.assertEqual((info['width_pixels'], info['height_pixels']), (8192, 512))
        self.assertEqual((info['spawn_x_pixels'], info['spawn_y_pixels']), (256, 352))
        self.assertEqual(len(layout), 4096)
        self.assertEqual(len(flags), 184)
        self.assertEqual(len(up), 47 * 32)
        self.assertEqual(len(down), 47 * 32)
        self.assertEqual(up[22 * 32:23 * 32], bytes([255] * 32))
        self.assertEqual(down[22 * 32:23 * 32], bytes([31] * 32))
        extracted = ROOT / 'src/data/lv_ghz.tileflags'
        if extracted.exists():
            self.assertEqual(flags, extracted.read_bytes())

    def test_rom_revision_checked(self):
        with self.assertRaisesRegex(ValueError, 'revision'):
            mod.extract(bytes(262144))


if __name__ == '__main__':
    unittest.main()
