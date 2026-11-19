#!/bin/sh
# GEARSYSTEM_DIR points to a Gearsystem source checkout; needs gcc and g++.
set -eu
: "${GEARSYSTEM_DIR:?Set GEARSYSTEM_DIR to a Gearsystem source checkout}"
cd "$(dirname "$0")/../../.."
build=build/sg1000/gearsystem-test
mkdir -p "$build"
src="$GEARSYSTEM_DIR/src"
miniz="$GEARSYSTEM_DIR/platforms/shared/dependencies/miniz"
gcc -O2 -I"$miniz" -c "$miniz/miniz.c" -o "$build/miniz.o"
gcc -O2 -c "$src/audio/emu2413/emu2413.c" -o "$build/emu2413.o"
g++ -O1 -std=c++11 -I"$src" -I"$miniz" \
    port/sg1000/prototype/gearsystem_test.cpp "$src"/*.cpp "$src"/audio/*.cpp \
    "$build/miniz.o" "$build/emu2413.o" -o "$build/test"
"$build/test" out/sonic-physics.sg

# Probe ROM uses the real runtime routines, without entering gameplay.
: "${WLA_Z80:=wla-z80}"
: "${WLALINK:=wlalink}"
"$WLA_Z80" -D GHZ_PROBE=1 -o "$build/probe.o" port/sg1000/prototype/main.asm
printf '[objects]\n%s\n' "$build/probe.o" > "$build/probe.lnk"
"$WLALINK" -r "$build/probe.lnk" "$build/probe.sg"
python3 - "$build/types.bin" <<'PYCODE'
import sys
from pathlib import Path
sys.path.insert(0, 'port/sg1000')
import prepare_ghz_layout
_, layout, flags, _, _ = prepare_ghz_layout.extract(Path('baserom/sonic1.sms').read_bytes())
Path(sys.argv[1]).write_bytes(bytes(flags[t] & 63 for t in layout))
PYCODE
g++ -O1 -std=c++11 -I"$src" -I"$miniz" \
    port/sg1000/prototype/ghz_probe_test.cpp "$src"/*.cpp "$src"/audio/*.cpp \
    "$build/miniz.o" "$build/emu2413.o" -o "$build/ghz-probe-test"
"$build/ghz-probe-test" "$build/probe.sg" "$build/types.bin" build/sg1000/prototype/ghz_floor_profiles.bin
