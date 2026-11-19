import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'port/sg1000'))
import prepare_audio_rings as prep


class AudioRingPreparationTest(unittest.TestCase):
    def test_ring_encoding_and_coordinates(self):
        # First, second, both, and an alternate high-bit tile; below $79 is empty.
        layout = bytes([0x78, 0x79, 0x7a, 0x7b, 0xf9, 0x00, 0x7b, 0x00])
        self.assertEqual(prep.ghz_rings(layout, 4, 2),
                         [(32, 8), (80, 8), (96, 8), (112, 8),
                          (0, 40), (64, 40), (80, 40)])

    def test_invalid_dimensions(self):
        for width, height in [(0, 1), (1, 0), (2, 2)]:
            with self.assertRaises(ValueError):
                prep.ghz_rings(bytes([0]), width, height)

    def test_original_rom_extraction(self):
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        rings, songs, info = prep.extract(rom.read_bytes())
        self.assertEqual(len(rings), 107)
        self.assertEqual(len(set(rings)), 107)
        self.assertIn((912, 200), rings)
        self.assertIn((928, 200), rings)
        self.assertEqual(info['title']['channel_offsets'], [10, 140, 218, 316])
        self.assertEqual(info['ghz']['channel_offsets'], [10, 372, 717, 1276])
        for name, filename in [('title', 'title_screen.song'), ('ghz', 'lv_ghz.song')]:
            exported = ROOT / 'src/data' / filename
            if exported.exists():
                self.assertEqual(songs[name], exported.read_bytes())

    def test_sprite_patterns(self):
        self.assertEqual(prep.opaque_patterns(bytes([0x80, 0x40, 0x20, 0x10] * 8)), bytes([0xf0] * 8))
        with self.assertRaises(ValueError):
            prep.opaque_patterns(bytes(31))
        rom = ROOT / 'Sonic The Hedgehog (USA, Europe, Brazil) (En).sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        ring, hud = prep.ring_and_hud_art(rom.read_bytes())
        self.assertEqual(len(ring), 6 * 4 * 8)
        self.assertEqual(len(hud), 24 * 8)
        self.assertEqual(ring[:32], b''.join(hud[i*8:(i+1)*8] for i in (20, 22, 21, 23)))

    def test_reject_wrong_rom(self):
        with self.assertRaises(ValueError):
            prep.extract(bytes(262144))


if __name__ == '__main__':
    unittest.main()
