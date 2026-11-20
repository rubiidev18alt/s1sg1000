import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'port/sg1000'))
sys.path.insert(0, str(ROOT / 'port/sg1000/prototype'))
import prepare_audio_rings
import prepare_music


class MusicPreparationTest(unittest.TestCase):
    def test_loops_rests_and_volume(self):
        # A tiny song with one repeated pair and an explicit restart.
        channel = bytes([0x81, 12, 0x8a, 3, 0x88, 0x86,
                         0x10, 0, 0x8c, 0x7f, 0, 0x87, 2, 16, 0, 0xff])
        song = bytes([10, 0, 26, 0, 26, 0, 26, 0, 0, 0]) + channel
        events, restart = prepare_music.decode(song, 0, 1, 1)
        self.assertEqual(restart, 0)
        self.assertEqual(events, [(3, 0x10, 3), (3, 0x7f, 15),
                                  (3, 0x10, 4), (3, 0x7f, 15)])

    def test_packed_noise_event(self):
        self.assertEqual(prepare_music.noise_event(12, 9), 0xc9)
        for duration, volume in ((0, 0), (16, 0), (1, 16), (1, -1)):
            with self.assertRaises(ValueError):
                prepare_music.noise_event(duration, volume)

    def test_invalid_bytecode_is_rejected(self):
        header = bytes([10, 0, 12, 0, 12, 0, 12, 0, 0, 0])
        with self.assertRaises(ValueError):
            prepare_music.decode(header + bytes([0x91, 0xff]), 0, 1, 1)
        with self.assertRaises(ValueError):
            prepare_music.decode(header + bytes([0x87, 0]), 0, 1, 1)

    def test_original_songs(self):
        rom = ROOT / 'baserom/sonic1.sms'
        if not rom.exists():
            self.skipTest('user-supplied ROM absent')
        _, songs, _ = prepare_audio_rings.extract(rom.read_bytes())
        for name, tempo, count, restart in [
            ('title', (5, 4), [40, 28], [39, 27]),
            ('ghz', (1, 1), [156, 282], [52, 126]),
        ]:
            decoded = [prepare_music.decode(songs[name], c, *tempo) for c in (0, 1)]
            self.assertEqual([len(events) for events, _ in decoded], count)
            self.assertEqual([loop for _, loop in decoded], restart)
            if name == 'ghz':
                # The two arranged parts enter their loop together and have
                # equal loop duration, so they don't drift apart on repeat.
                self.assertEqual([sum(x[0] for x in e[:r]) for e, r in decoded], [864, 864])
                self.assertEqual([sum(x[0] for x in e[r:]) for e, r in decoded], [2304, 2304])
        title_noise, title_restart = prepare_music.decode(songs['title'], 3, 5, 4)
        ghz_noise, ghz_restart = prepare_music.decode(songs['ghz'], 3, 1, 1)
        self.assertEqual((len(title_noise), title_restart), (35, 34))
        self.assertEqual((len(ghz_noise), ghz_restart), (72, 8))
        self.assertEqual(sum(event[0] for event in ghz_noise[:ghz_restart]), 96)
        self.assertEqual(sum(event[0] for event in ghz_noise[ghz_restart:]), 768)
        self.assertEqual({event[1] for event in ghz_noise}, {0x70, 0x71})
        clear_channels = [prepare_music.decode(songs['clear'], c, 4, 3) for c in (0, 1, 3)]
        self.assertEqual([len(events) for events, _ in clear_channels], [14, 14, 23])
        self.assertEqual([sum(e[0] for e in events) for events, _ in clear_channels[:2]], [328, 328])
        score = prepare_music.compile_score(songs)
        self.assertIn('music_clear_0:', score)
        self.assertIn('music_title_0:', score)
        self.assertIn('.dw music_ghz_1_loop', score)
        self.assertIn('.dw music_ghz_3_loop', score)
        self.assertIn('music_title_3:', score)


if __name__ == '__main__':
    unittest.main()
