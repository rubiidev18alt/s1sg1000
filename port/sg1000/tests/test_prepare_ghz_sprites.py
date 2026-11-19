import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_ghz_sprites as ghz


class GreenHillSpritesTest(unittest.TestCase):
    def test_planar_conversion_preserves_transparency(self):
        palette = bytes([0, 0x3f, 0, 0x3f] + [0] * 12)
        # Nonzero index 1 and 3 pixels; SMS colour zero is transparent.
        tiles = bytes([0xc0, 0x40, 0, 0] + [0] * 28) + bytes(32)
        patterns, colours = ghz.convert_tiles(tiles, palette)
        self.assertEqual(patterns, bytes([0xc0] + [0] * 15))
        self.assertEqual(colours, bytes([15, 0]))

    def test_source_maps_skip_empty_and_terminate_by_row(self):
        rom = bytes([0xfe, 2, 0xff, 0xff, 0xff, 0xff,
                     4, 6, 0xff, 0xff, 0xff, 0xff,
                     0xff] + [0] * 5)
        self.assertEqual(ghz.read_frame_map(rom, 0, 0, 128), [
            {'x': 8, 'y': 0, 'top_tile': 2, 'bottom_tile': 3},
            {'x': 0, 'y': 16, 'top_tile': 4, 'bottom_tile': 5},
            {'x': 8, 'y': 16, 'top_tile': 6, 'bottom_tile': 7}])
        with self.assertRaises(ValueError):
            ghz.read_frame_map(bytes([3] + [0xff] * 17), 0, 0, 128)

    def test_rejects_bad_inputs_before_output(self):
        with self.assertRaises(ValueError):
            ghz.convert_tiles(bytes(31), bytes(16))
        with self.assertRaises(ValueError):
            ghz.convert_tiles(bytes(32), bytes(15))
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'generated'
            with self.assertRaises(ValueError):
                ghz.prepare(b'wrong rom', b'', b'', out)
            self.assertFalse(out.exists())

    def test_extracted_rom_integration_when_available(self):
        root = Path(__file__).resolve().parents[3]
        rom = root / 'baserom/sonic1.sms'
        data = root / 'src/data'
        if not (rom.exists() and (data / 'lv_ghz.art2000').exists()):
            self.skipTest('supported ROM and extracted assets not available')
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            result = ghz.prepare(rom.read_bytes(), (data / 'lv_ghz.art2000').read_bytes(),
                                 (data / 'lv_ghz.pal3').read_bytes(), out)
            self.assertEqual(result['tile_count'], 128)
            self.assertEqual(len((out / 'patterns.bin').read_bytes()), 1024)
            self.assertEqual(len((out / 'colours.bin').read_bytes()), 128)
            manifest = json.loads((out / 'manifest.json').read_text())
            self.assertEqual([len(manifest['objects'][n]) for n in ghz.OBJECTS], [4, 6, 4])
            self.assertEqual(manifest['objects']['motobug'][0][0]['top_tile'], 0x60)
            self.assertEqual(manifest['objects']['buzz_bomber'][0][0]['x'], 8)


if __name__ == '__main__':
    unittest.main()
