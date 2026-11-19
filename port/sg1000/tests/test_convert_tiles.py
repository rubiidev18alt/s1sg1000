import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('convert_tiles', Path(__file__).resolve().parents[1] / 'convert_tiles.py')
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class ConvertTilesTest(unittest.TestCase):
    def test_sms_colour_channels(self):
        self.assertEqual(converter.sms_colour(0x03), (255, 0, 0))
        self.assertEqual(converter.sms_colour(0x0c), (0, 255, 0))
        self.assertEqual(converter.sms_colour(0x30), (0, 0, 255))

    def test_black_and_white_planar_rows(self):
        palette = bytes([0, 0x3f] + [0] * 14)
        patterns, colours = converter.convert(bytes([0xaa, 0, 0, 0] * 8), palette)
        self.assertEqual(patterns, bytes([0xaa] * 8))
        self.assertEqual(colours, bytes([0xf1] * 8))

    def test_reject_incomplete_inputs(self):
        with self.assertRaises(ValueError):
            converter.convert(bytes(31), bytes(16))
        with self.assertRaises(ValueError):
            converter.convert(bytes(32), bytes(15))

    def test_multiple_tiles_and_solid_row(self):
        patterns, colours = converter.convert(bytes(64), bytes(16))
        self.assertEqual(patterns, bytes(16))
        self.assertEqual(colours, bytes([0x11] * 16))


if __name__ == '__main__':
    unittest.main()
