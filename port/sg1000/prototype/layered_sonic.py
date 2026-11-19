"""Convert Sonic's 24x32 SMS art to two-colour TMS 16x16 sprite layers."""
from convert_tiles import TMS, distance, sms_colour


def convert(frame, palette):
    if len(frame) != 288 or len(palette) != 16:
        raise ValueError('expected a 288-byte 3bpp Sonic frame and 16-byte palette')
    pixels = [[0] * 32 for _ in range(32)]
    for tile in range(12):
        tx = (tile // 2 % 3) * 8
        ty = (tile // 6) * 16 + (tile % 2) * 8
        for row in range(8):
            planes = frame[tile * 24 + row * 3:tile * 24 + row * 3 + 3]
            for col in range(8):
                pixels[ty + row][tx + col] = sum(
                    ((planes[p] >> (7 - col)) & 1) << p for p in range(3))
    rgb = [sms_colour(c) for c in palette[:8]]
    costs = [[distance(src, dst) for dst in TMS[1:]] for src in rgb]
    patterns, colours = bytearray(), bytearray()
    # Two layers for each 16x16 quadrant. Each mask is disjoint. This uses
    # exactly four hardware sprites on any scanline (two columns x two layers).
    for qy in range(2):
        for qx in range(2):
            counts = [0] * 8
            for row in range(16):
                for col in range(16):
                    counts[pixels[qy * 16 + row][qx * 16 + col]] += 1
            if sum(counts[1:]) == 0:
                chosen = (0, 0)
            else:
                _, a, b = min(
                    (sum(counts[p] * min(costs[p][a - 1], costs[p][b - 1])
                         for p in range(1, 8)), a, b)
                    for a in range(1, 16) for b in range(a, 16))
                chosen = (a, b)
            for layer, colour in enumerate(chosen):
                mask = bytearray()
                # TMS 16x16 sprite patterns: top-left, bottom-left,
                # top-right, bottom-right (four consecutive 8-byte tiles).
                for half_x in range(2):
                    for row in range(16):
                        value = 0
                        for col in range(8):
                            p = pixels[qy * 16 + row][qx * 16 + half_x * 8 + col]
                            selected = (0 if costs[p][chosen[0] - 1] <= costs[p][chosen[1] - 1] else 1) if p and colour else -1
                            value = (value << 1) | (selected == layer)
                        mask.append(value)
                patterns.extend(mask)
                colours.append(colour if any(mask) else 0)
    return bytes(patterns), bytes(colours)
