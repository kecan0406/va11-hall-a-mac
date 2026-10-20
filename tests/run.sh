#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
SRC="$REPO/build/butterscotch"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

[ -f "$SRC/src/backends/appkit_mouse.h" ] || "$REPO/build.sh" --build-only

echo "== launcher"
"$HERE/launcher_test.sh"

echo "== installer"
"$HERE/install_test.sh"

echo "== scenario compiler"
python3 -m unittest discover -s "$HERE" -p '*_test.py'

echo "== mouse mapping (patch 0002)"
cc -Wall -Wextra -framework Cocoa -I "$SRC/src/backends" "$HERE/appkit_mouse_test.m" -o "$OUT/appkit_mouse_test"
"$OUT/appkit_mouse_test"

echo "== Ogg demuxer (patch 0001)"
python3 -I - "$SRC/src/audio/miniaudio/ma_audio_system.c" "$HERE/ogg_demux_test.c.in" "$OUT/ogg_demux_test.c" <<'PY'
import re, sys
source, template, out = sys.argv[1:4]
block = re.search(r"typedef struct \{\s*const AudioEntry\* entry;.*?(?=// ===\[ Helpers \]===)", open(source).read(), re.S)
if not block:
    raise SystemExit("can't find the Ogg demuxer in the runner source")
open(out, "w").write(open(template).read().replace("@DEMUX@", block.group(0)))
PY
cc -std=gnu2x -Wall -Wno-unused-function -I "$SRC/vendor/stb/ds" "$OUT/ogg_demux_test.c" -o "$OUT/ogg_demux_test"
"$OUT/ogg_demux_test"

echo
echo "All unit tests passed."
