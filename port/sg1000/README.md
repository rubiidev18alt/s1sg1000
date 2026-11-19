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

## Sonic sprite conversion (early work)

`convert_sonic.py` converts an extracted 288-byte `.sonicuncart` frame (twelve
8x8, row-interleaved 3bpp tiles) plus the corresponding 16-byte SMS sprite
palette into 96 TMS 8x8 pattern bytes and 12 colour bytes. Source colour zero
is transparent. Since a TMS sprite has just one colour, each tile is reduced to
one opaque colour; black outlines and other colour details are lost. Tile order
is retained, but placement, flipping, animation and sprite attributes are not
implemented. The runtime must also respect the TMS limit of four sprites on a
scanline. This is a conversion building block, not a finished Sonic renderer.

```
python3 port/sg1000/convert_sonic.py src/data/sonic_06_r.sonicuncart sprite_palette.bin sonic_patterns.bin sonic_colours.bin
```

The normal SMS physics constants can be found in `src/diet.asm` at 01:4966
(speed cap $0300, jump velocity $FC80, gravity $0038), with acceleration,
braking and coasting parameters at 01:4DCB. The jump effect starts at 03:7B27;
braking and rolling are at 03:7B98 and 03:7C18. These are references for the
future SG-1000 implementation, not yet ported physics or sound routines.

To prepare all 84 left/right frames from the supported ROM:

```
mkdir -p src/data
python3 tools/rom_unpack.py baserom/sonic1.sms annot/sonic1.cfg src/whole.asm
python3 port/sg1000/prepare_sonic.py
```

The resulting files are written under `build/sg1000/sonic/` (ignored by Git).
The tool uses the sprite half of the Green Hill Zone palette. Other levels may
use different palettes, and this is still a lossy, single-colour conversion;
no playable game or sound/physics code is produced by this step.

## Playable physics sandbox

The separate prototype builds a 32 KiB SG-1000 ROM with a black background,
a 768-pixel-wide white test course with multiple stepped hills. Move with left/right; button 1 jumps.
Holding button 1 produces a higher jump. Press down while moving to roll;
rolling slows on flat or uphill ground, but retains speed downhill. It ends
when Sonic stops or jumps. Reset the emulator to restart. At the ZONE SELECT menu, press and release button 1 or 2 to enter TEST.
The menu font is extracted from the SMS world-map art and reduced to white
foreground pixels. Run it
in Gearsystem's SG-1000 mode (the `.sg` extension should select it; force
SG-1000 if needed). NTSC timing is the reference.

Install WLA-DX (`wla-z80` and `wlalink`) and Python 3, put the supported SMS
ROM at `baserom/sonic1.sms`, and from the repository root run:

```
python3 port/sg1000/prototype/build.py
```

The result is `out/sonic-physics.sg`. The build validates and unpacks the ROM
and generates intermediate assets under `build/`; both directories are ignored.
Custom assembler paths can be supplied with `--wla-z80` and `--wlalink`.

This is a **physics experiment**, not a direct port of Sonic's complete
movement engine. Acceleration ($10), braking ($30), coasting ($08), maximum
normal horizontal speed ($0300), jump velocity ($FC80), jump hold (16 frames),
and gravity ($38) are based on the SMS disassembly. Floor collision is a
simple centre-point height lookup with 8-pixel steps, not the original slopes,
full SMS slope and rolling physics, wall collision, inertia or level objects. It has no sound.
The camera follows horizontally and vertically in 8-pixel increments; the
TMS9918 does not support smooth hardware scrolling, and redraws may tear.
Sprite colours and animation timing are approximate. There are no enemies or complete levels.

Tests include the Python converter suite and an optional actual Gearsystem
core smoke test (build the ROM first, with a Gearsystem source checkout and a
C/C++ compiler available):

```
python3 -m unittest discover -s port/sg1000/tests
GEARSYSTEM_DIR=/path/to/Gearsystem port/sg1000/prototype/test_gearsystem.sh
```

The emulator test covers acceleration, reversal, edge limits, both camera axes, hills, jump
height, landing, menu confirmation, animation preview, rolling friction and both downhill directions; it does not establish cycle-accurate SMS physics.

### Sprite and animation experiment

The sandbox uses two overlapping 16x16 TMS sprites per quadrant, choosing up to
two fixed-palette colours for each quadrant. The 24x32 source art is padded
to 32x32. This improves colour detail but uses all four available sprites per
scanline, so adding enemies will require a different sprite budget or flicker.
All 42 frame indices are included for both directions. Walking, jumping,
looking, braking and idle use selected frames; other game actions are not
implemented. To inspect all frames, hold button 2 and tap left/right. Releasing
button 2 resumes the sandbox; the preview does not advance physics.
