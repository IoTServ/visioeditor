#!/bin/sh
# Build the libvisio FFI shim used by the differential tests.
#
# Prerequisites (macOS): `brew install libvisio` (pulls in librevenge).
# The tests skip automatically when the resulting dylib is absent, so this
# build is optional for contributors who don't need the oracle.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

# librevenge's .pc transitively requires ICU, which Homebrew keeps keg-only, so
# add its pkgconfig dir explicitly.
ICU_PC_DIR="$(dirname "$(find /opt/homebrew /usr/local -name 'icu-i18n.pc' 2>/dev/null | head -1)")"
export PKG_CONFIG_PATH="${ICU_PC_DIR}:/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

MODS="libvisio-0.1 librevenge-0.0 librevenge-generators-0.0 librevenge-stream-0.0"
CFLAGS="$(pkg-config --cflags $MODS)"
LIBS="$(pkg-config --libs $MODS)"

OUT="$DIR/libvisio_shim.dylib"
clang++ -std=c++17 -O2 -fPIC -shared \
  -Wl,-rpath,/opt/homebrew/lib -Wl,-rpath,/usr/local/lib \
  "$DIR/libvisio_shim.cpp" \
  $CFLAGS $LIBS \
  -o "$OUT"

echo "built $OUT"
