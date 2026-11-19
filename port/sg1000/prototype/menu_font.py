"""Extract the SMS world-map font from HY-compressed, unpacked ROM art."""
import struct

# The original level-select strings in mods/compress/lselect.inc identify the
# character indices. Z is $3F in the same world-map font.
GLYPHS = {'Z': 0x3F, 'O': 0x52, 'N': 0x51, 'E': 0x44,
          'S': 0x70, 'L': 0x43, 'C': 0x36, 'T': 0x80}


def decode_hy(art):
    if len(art) < 8:
        raise ValueError('truncated HY header')
    magic, offsets_at, rows_at, row_count = struct.unpack_from('<HHHH', art)
    if magic != 0x5948 or row_count % 8 or offsets_at != 8 + row_count // 8 or not offsets_at <= rows_at <= len(art):
        raise ValueError('invalid HY art header')
    masks, offsets, rows = art[8:offsets_at], art[offsets_at:rows_at], art[rows_at:]
    output = bytearray()
    oi = ri = 0
    for mask in masks:
        for bit in range(8):
            if mask & (1 << bit):
                if oi >= len(offsets):
                    raise ValueError('truncated HY offset')
                index = offsets[oi]
                oi += 1
                if index >= 0xF0:
                    if oi >= len(offsets):
                        raise ValueError('truncated HY long offset')
                    index = ((index - 0xF0) << 8) | offsets[oi]
                    oi += 1
                position = index * 4
            else:
                position = ri
                ri += 4
            if position + 4 > len(rows):
                raise ValueError('HY row outside row data')
            output.extend(rows[position:position + 4])
    if oi != len(offsets) or ri != len(rows):
        raise ValueError('unexpected trailing HY data')
    return bytes(output)


def font_patterns(art):
    tiles = decode_hy(art)
    if len(tiles) < (max(GLYPHS.values()) + 1) * 32:
        raise ValueError('world-map art does not contain the expected font')
    output = bytearray()
    for index in GLYPHS.values():
        for y in range(8):
            p = index * 32 + y * 4
            # On this source palette, $F is the bright letter, $B the shadow
            # and $D the background. Graphics I gets a 1-bit white glyph.
            output.append(tiles[p] & tiles[p + 1] & tiles[p + 2] & tiles[p + 3])
    return bytes(output)
