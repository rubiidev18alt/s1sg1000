import sys
import tempfile
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_sonic


class PrepareSonicTest(unittest.TestCase):
    def test_converts_both_directions_and_uses_sprite_palette(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / 'data'
            output = Path(tmp) / 'output'
            data.mkdir()
            (data / 'lv_ghz.pal3').write_bytes(bytes(16) + bytes([0, 63] + [0] * 14))
            frame = bytes([128, 0, 0] + [0] * 285)
            for direction in ('r', 'l'):
                for i in range(0x2a):
                    (data / 'sonic_{:02X}_{}.sonicuncart'.format(i, direction)).write_bytes(frame)
            self.assertEqual(prepare_sonic.prepare(data, output), 84)
            self.assertEqual(len(list(output.iterdir())), 168)
            self.assertEqual((output / 'sonic_0a_l.colours').read_bytes()[0], 15)
            self.assertEqual((output / 'sonic_29_r.patterns').read_bytes()[0], 128)

    def test_missing_frame_does_not_create_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / 'data'
            data.mkdir()
            (data / 'lv_ghz.pal3').write_bytes(bytes(32))
            output = Path(tmp) / 'output'
            with self.assertRaises(FileNotFoundError):
                prepare_sonic.prepare(data, output)
            self.assertFalse(output.exists())
