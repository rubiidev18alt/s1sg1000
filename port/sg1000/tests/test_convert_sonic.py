import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import convert_sonic


class SonicSpriteTest(unittest.TestCase):
    def test_transparency_and_plane_order(self):
        frame = bytearray(288)
        # Pixel indices 1, 2, 4 on the first three pixels.
        frame[:3] = bytes((0x80, 0x40, 0x20))
        palette = bytes([0, 0x3f, 0x3f, 0, 0x3f] + [0] * 11)
        patterns, colours = convert_sonic.convert(frame, palette)
        self.assertEqual(patterns[0], 0xe0)
        self.assertEqual(patterns[1:], bytes(95))
        self.assertEqual(colours, bytes([15] + [0] * 11))

    def test_colour_is_chosen_across_all_rows(self):
        frame = bytearray(288)
        frame[0:3] = bytes((0x80, 0, 0))
        frame[3:6] = bytes((0xff, 0, 0))
        patterns, colours = convert_sonic.convert(frame, bytes([0, 0x3f] + [0] * 14))
        self.assertEqual(patterns[:2], bytes((0x80, 0xff)))
        self.assertEqual(colours[0], 15)

    def test_input_validation(self):
        with self.assertRaises(ValueError):
            convert_sonic.convert(bytes(287), bytes(16))
        with self.assertRaises(ValueError):
            convert_sonic.convert(bytes(288), bytes(8))


if __name__ == '__main__':
    unittest.main()
