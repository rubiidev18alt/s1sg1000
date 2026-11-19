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
rolling slows on flat or uphill ground, but retains speed downhill. After
starting a roll, hold up and the direction of travel on a descent to
accelerate (an approximation, capped at 12 pixels per frame). Down and the
direction of travel also works. Release
down and press against the direction of travel to unroll and brake; the roll
also ends when Sonic stops or jumps. Reset the emulator to restart. At the ZONE SELECT menu, tap button 2 to switch between TEST and GHZ1;
press and release button 1 to enter either test level.
The menu font is extracted from the SMS world-map art and reduced to white
foreground pixels. Run it
in Gearsystem's SG-1000 mode (the `.sg` extension should select it; force
SG-1000 if needed). NTSC timing is the reference.

In either zone, tap button 2 to toggle debug flight. Use the D-pad to move freely in
all four directions, including diagonally, through terrain without gravity;
the camera follows and movement stays within that zone's player bounds. Tap
button 2 again to return to normal physics, with momentum cleared. Exiting
while inside or below terrain may snap Sonic back onto the floor.

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
gravity ($38), and flat rolling drag ($04) are based on the SMS disassembly.
Grounded roll braking follows the original opposite-direction input behavior.
Downhill friction exemption and direction-held roll acceleration are
prototype approximations in both zones, not the full SMS slope physics. TEST uses a
simple centre-point height lookup with 8-pixel steps. GHZ1 uses the original
floor profiles with centre and inset foot sensors to bridge missed contacts
at platform edges. Full-solid blocks stop motion from either side, and floor
tiles connected to solid terrain also block upward motion. Detached platforms
remain one-way. Wall and ceiling probes are approximate, and moving
platforms and most original level objects are not implemented.
There is no complete SMS slope and rolling physics or full music driver yet.
In both levels the camera is offset 16 pixels to the right of its original
prototype position, giving more view ahead. The camera follows horizontally
and vertically in 8-pixel increments; the
TMS9918 does not support smooth hardware scrolling, and redraws may tear.
Unchanged Sonic patterns and HUD tiles are cached to reduce VRAM traffic; PSG
updates run after graphics writes to avoid delaying them with audio wait states.
Sprite colours and animation timing are approximate. There are no enemies or complete levels.

Tests include the Python converter suite and an optional actual Gearsystem
core smoke test (build the ROM first, with a Gearsystem source checkout and a
C/C++ compiler available):

```
python3 -m unittest discover -s port/sg1000/tests
GEARSYSTEM_DIR=/path/to/Gearsystem port/sg1000/prototype/test_gearsystem.sh
```

The emulator test covers acceleration, reversal, edge limits, both camera axes, hills, jump
height, landing, menu confirmation, debug flight, animation preview, rolling friction, GHZ
wall/ceiling/one-way collisions, the GHZ camera limit, and both downhill
directions; it does not establish cycle-accurate SMS physics.

### Sprite and animation experiment

The sandbox uses two overlapping 16x16 TMS sprites per quadrant, choosing up to
two fixed-palette colours for each quadrant. The 24x32 source art is padded
to 32x32. This improves colour detail but uses all four available sprites per
scanline, so adding enemies will require a different sprite budget or flicker.
All 42 frame indices are included for both directions. Walking, jumping,
looking, braking and idle use selected frames; other game actions are not
implemented. To inspect all frames in TEST, hold buttons 1 and 2 together
and tap left/right in either zone. Releasing the viewer controls resumes
the previous mode; the preview does not advance physics. Button 2 alone
toggles debug flight in either zone.

The waiting animation starts after 360 idle frames, following the SMS bored
frame sequence and its loop point. Other animation timing remains approximate.

### Green Hill sprite asset preparation (not loaded in the prototype)

After extracting the supported ROM as described above, run:

```
python3 port/sg1000/prepare_ghz_sprites.py
```

This decodes the GHZ `$2000` sprite art bank and converts its 128 SMS 4bpp
8x8 tiles to TMS monochrome masks and per-tile colours using the GHZ SMS sprite
palette. It writes `patterns.bin`, `colours.bin`, and `manifest.json` to
`build/sg1000/ghz_sprites/` (generated, ignored). The manifest preserves the
original sprite-map cell coordinates and source tile indices for Crabmeat,
Buzz Bomber and Motobug animation frames. Source maps are read only from the
verified ROM; no game data is fetched or committed by this script.

This is a first-pass conversion: the single-colour tiles lose detail, and
animation timing, sprite limits, enemy behavior, collision, palettes for other
zones, and runtime integration are not implemented. In particular, the
prototype's two-layer Sonic already uses the TMS four-sprites-per-scanline
budget. The GHZ1 test level does not load these enemy assets.

The sandbox's walk and roll animation phases now advance with horizontal
speed, based on the SMS code; run, jump and skid also use the corresponding
SMS frame sequences. The prototype physics and frame timings are still not a
complete or cycle-exact port.

## GHZ1 layout and test level

`python3 port/sg1000/prepare_ghz_layout.py --rom baserom/sonic1.sms`
extracts the supported SMS revision's 256×16 layout of 32-pixel metatiles
(8192×512 pixels), tile flags, and 32-column floor and ceiling collision
profiles to `build/sg1000/ghz1_layout/`. Offsets are signed bytes, with $80
meaning no surface. The manifest records the original starting point and
camera limits. The ROM is checked by SHA-256; generated data remains ignored.
The GHZ1 menu option starts a second test level using the original
8192×512 collision layout and original spawn position. A cyan background,
two-green grass and checkerboard soil/walls show the terrain. The grass is
adapted from the original SMS art with a cleaner highlighted edge; the soil
uses the original alternating checker-tile layout, anchored in world space.
The SG-1000 palette has no exact match for the original brown and orange.
Placement still follows the collision silhouette rather than the original
graphics tilemap, so scenery is not shown and slopes remain approximate. Full-solid blocks stop Sonic
at their sides and undersides. Floor tiles connected to solid blocks also
have solid undersides; detached platforms remain semisolid, so Sonic can jump
through them from below. Connectedness is a prototype approximation, not
original SMS material data, and other side collision is still incomplete.
The SMS GHZ1 tile-special data contains one ramp launcher, at world position
(2272,416). Its background-tile artwork is a two-pattern approximation of
the original ramp, rather than separate hardware sprites (Sonic already uses
the scanline sprite budget). Start rolling, then hold up and right down the
approach and through the ramp. A speed above 3 pixels per frame is needed
to launch. The launch keeps horizontal momentum, sets upward velocity based on
speed, plays an approximate ramp sound and limits camera catch-up to one tile
per update on each axis while airborne. High launches are clamped at the top
of the map, and offscreen Sonic is hidden until the camera catches up. This
is an approximation, not the original full physics or sound driver.
Original moving platform objects are not yet implemented. Falling below the
map respawns Sonic. No enemies or other objects are present.

The prototype packs the collision-profile IDs into row-indexed runs, with the
floor profiles used by the layout. Z80 routines read the metatiles and their
pixel-accurate floor offsets without storing the map in the SG-1000's 1 KiB
RAM. The GHZ1 camera uses a 16-bit horizontal tile coordinate and follows both
axes up to the original GHZ1 right camera limit, x=6336. Sonic is clamped
at x=6559, just inside that camera boundary, rather than entering the unused
end of the larger layout. A precomputed run-length-encoded silhouette assigns
grass to exposed upper surfaces and soil to other solid cells.
A Gearsystem movement test recorded 120 simulation updates in 120 video
frames in the starting area; this is not a guarantee for every situation.
The 8-pixel redraw may still tear, and movement remains provisional rather
than faithful SMS physics.

The Gearsystem test also builds a separate probe ROM to exercise the actual
Z80 lookup routines. Set `WLA_Z80` and `WLALINK` if those tools are not on
`PATH`, as well as `GEARSYSTEM_DIR` as usual.

## Rings and music preparation

`python3 port/sg1000/prepare_audio_rings.py --rom baserom/sonic1.sms`
validates the supported ROM and extracts the title and GHZ song streams, the
107 GHZ1 ring positions, and monochrome versions of the original six ring
animation frames and ring HUD/digit art into `build/sg1000/audio_rings/`.
The original level stores rings as bits in 32×32 metatile IDs, not object
placements; the extracted positions are the top-left of each 16×16 ring.
The manifest includes the original four relative song-channel offsets.

The prototype now includes four test-course rings and the 107 original GHZ1
ring positions. All six original ring frames animate as monochrome yellow
background tiles. The original ring HUD icon uses the same yellow, while the
two-digit counter is white. Collected rings disappear and are tracked until reset or GHZ respawn;
the counter wraps at 100 as on SMS, but the extra life is not implemented.
Fully visible rings are drawn when the camera changes (partially clipped rings are not drawn).

The prototype plays jump, roll, brake, and ring pickup sound effects using
PSG tone channel 2 only. Their note lengths, pitch sweeps, repeated notes and
volume steps follow the SMS effects data, rendered as precomputed frame
sequences rather than the original sound driver. Effect priority and retrigger
behavior remain simplified, and the result has not been verified by listening
against the original hardware. Other Sonic sounds are not yet implemented.

A first music port plays simplified arrangements of the original SMS title
theme on zone select and Green Hill music in GHZ1; TEST is silent. The build
compiles two tone parts and the original noise-part rhythms into frame-timed
note/volume events, preserving song loops and note timing. The noise percussion
uses a fixed clock, so effects on tone channel 2 cannot alter its pitch. Simple
volume decay has been added to the tones and the two percussion presets, but
the original envelopes, vibrato, pitch bends and legato are still approximate
or omitted, as is the third tone part. The title stream ends in silence as in
its extracted data. This is not a complete or listening-verified music port.
Generated ROM-derived assets remain ignored.
