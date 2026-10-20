#!/bin/bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
REL="$REPO/build/release"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$REL/va11-hall-a-mac.zip" ] || "$REPO/release.sh" >/dev/null

RESOURCES="$WORK/steam/steamapps/common/VA-11 HALL-A/Fake.app/Contents/Resources"
APP_DIR="$WORK/Applications"
DATA="$WORK/data"
APP="$APP_DIR/VA-11 Hall-A (native).app"
mkdir -p "$RESOURCES"
echo game > "$RESOURCES/game.ios"
echo icon > "$RESOURCES/icon.icns"

failures=0
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}

export VA11_STEAM_RESOURCES="$RESOURCES" VA11_APP_DIR="$APP_DIR" VA11_DATA_DIR="$DATA" VA11_NO_DIALOG=1

cat "$REL/install.sh" | /bin/bash -s -- --release-url "file://$REL" >"$WORK/out.txt" 2>&1

check "release: the piped installer finishes" 'grep -q "All set" "$WORK/out.txt"'
check "release: the runner has an Apple Silicon and an Intel part" 'file -b "$APP/Contents/MacOS/butterscotch" | grep -q "universal binary with 2 architectures"'
check "release: the app is signed" 'codesign --verify --deep "$APP" 2>/dev/null'
check "release: the app finds the game" '[ "$(VA11_PREPARE_ONLY=1 "$APP/Contents/MacOS/VA-11 Hall-A")" = "$DATA/game.ios" ]'
check "release: the runner starts" '"$APP/Contents/MacOS/butterscotch" --help 2>&1 | grep -q "^Usage"'
if arch -x86_64 /usr/bin/true 2>/dev/null; then
  check "release: the Intel part of the runner starts too" 'arch -x86_64 "$APP/Contents/MacOS/butterscotch" --help 2>&1 | grep -q "^Usage"'
fi
check "release: the archive carries the license and where the source is" '
  unzip -l "$REL/va11-hall-a-mac.zip" | grep -q "LICENSE" && unzip -p "$REL/va11-hall-a-mac.zip" va11-hall-a-mac/SOURCE.txt | grep -q "github.com/ButterscotchRunner/Butterscotch"'
check "release: the archive matches its checksum" '(cd "$REL" && shasum -a 256 -c va11-hall-a-mac.zip.sha256 >/dev/null 2>&1)'

[ "$failures" -eq 0 ] && echo "PASS" || { echo "FAILED ($failures)"; exit 1; }
