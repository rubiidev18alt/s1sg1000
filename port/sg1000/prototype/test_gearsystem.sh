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
