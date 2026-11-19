import struct
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'prototype'))
import menu_font


class MenuFontTest(unittest.TestCase):
    def test_literal_and_reference_rows(self):
        # Eight rows: one literal, followed by seven references to row zero.
        data = struct.pack('<HHHH', 0x5948, 9, 16, 8) + b'\xfe' + bytes(7) + b'\x12\x34\x56\x78'
        self.assertEqual(menu_font.decode_hy(data), b'\x12\x34\x56\x78' * 8)

    def test_reject_bad_inputs(self):
        for data in (b'', bytes(8), struct.pack('<HHHH', 0x5948, 9, 9, 8) + b'\x00'):
            with self.assertRaises(ValueError):
                menu_font.decode_hy(data)

    def test_known_font_codepoints(self):
        self.assertEqual(menu_font.GLYPHS['Z'], 0x3f)
        self.assertEqual(menu_font.GLYPHS['T'], 0x80)
        self.assertEqual(set(menu_font.GLYPHS), set('ZONESELECT'))
