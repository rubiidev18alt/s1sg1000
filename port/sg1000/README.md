# SG-1000 port work

This is an initial asset conversion tool, **not a playable port**. The existing
SMS disassembly is not an SG-1000 program. Gearsystem's SG-1000 mode emulates
1 KiB of system RAM mirrored throughout $C000-$FFFF and a TMS9918-compatible
VDP; it does not make SMS mode-4 graphics, SMS RAM or the Sega mapper available
to an SG-1000 cartridge. Its SG-1000 memory rule maps a linear ROM at
$0000-$7FFF (and can expose additional data at $8000-$BFFF), not the SMS
banked 256 KiB address space. A full port requires major engine, level and art
redesign; no expansion or emulator-specific mapper is assumed here.

## Background tile conversion

`convert_tiles.py` takes **uncompressed** SMS planar 4bpp tiles (32 bytes per
tile, four plane bytes per row) and one raw 16-byte SMS CRAM palette. It emits
one 8-byte Graphics II pattern and one 8-byte colour record per tile. For
each row it picks the two opaque TMS colours with minimum squared RGB error;
pattern bits select the high colour nibble when set. The fixed TMS colour 0
(backdrop/transparent) is deliberately excluded. This is approximate: it does
not preserve SMS palette selection, flipping, priority, sprites or transparency.
The output is tile-major; the eventual runtime must arrange and upload it for
Graphics II's three screen thirds and enforce their character limits.

```
python3 port/sg1000/convert_tiles.py tiles.bin palette.bin patterns.bin colours.bin
python3 -m unittest discover -s port/sg1000/tests
```

The repository's game assets are extracted from a user-supplied ROM and may be
compressed or in other formats; they must be decoded to the inputs described
above first. This tool neither extracts a ROM nor produces a game ROM.
