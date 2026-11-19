import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'prototype'))
import layered_sonic


class LayeredSonicTests(unittest.TestCase):
    def test_transparency_and_two_colours(self):
        frame = bytearray(288)
        # Black and white opaque pixels on the first row, plus transparent.
        frame[0:3] = bytes([0x80, 0x40, 0])
        palette = bytes([0, 0, 0x3f] + [0] * 13)
        patterns, colours = layered_sonic.convert(frame, palette)
        self.assertEqual(len(patterns), 256)
        self.assertEqual(len(colours), 8)
        self.assertEqual((patterns[0], patterns[32]), (0x80, 0x40))
        self.assertEqual(colours[:2], bytes([1, 15]))
        self.assertEqual(colours[2:], bytes(6))

    def test_tile_layout(self):
        frame = bytearray(288)
        # Tile 6 begins the lower half of Sonic, at x=0 y=16.
        frame[6 * 24] = 0x80
        patterns, _ = layered_sonic.convert(frame, bytes(16))
        self.assertEqual(patterns[4 * 32], 0x80)
        self.assertEqual(sum(patterns), 128)

    def test_validation(self):
        with self.assertRaises(ValueError):
            layered_sonic.convert(bytes(287), bytes(16))
