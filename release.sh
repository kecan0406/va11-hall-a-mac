#!/bin/bash
set -euo pipefail

REPO=kecan0406/va11-hall-a-mac
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build/release"
STAGE="$OUT/va11-hall-a-mac"
ASSET=va11-hall-a-mac.zip

VERSION="${VA11_VERSION:-$(git -C "$HERE" describe --tags --always --dirty 2>/dev/null || echo dev)}"
COMMIT="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
BUTTERSCOTCH_COMMIT="$(sed -n 's/^BUTTERSCOTCH_COMMIT=//p' "$HERE/build.sh")"

"$HERE/build.sh" --universal --build-only

rm -rf "$OUT"
mkdir -p "$STAGE"
cp "$HERE/build/dist/butterscotch" "$STAGE/butterscotch"
cp "$HERE/app/launcher.sh" "$STAGE/launcher.sh"
cp "$HERE/install.sh" "$STAGE/install.sh"
cp "$HERE/LICENSE" "$STAGE/LICENSE"
printf '%s\n' "$VERSION" > "$STAGE/VERSION"
cat > "$STAGE/SOURCE.txt" <<EOF
This is the runner from https://github.com/ButterscotchRunner/Butterscotch (AGPL-3.0), commit $BUTTERSCOTCH_COMMIT,
with the patches in patches/ of https://github.com/$REPO (commit $COMMIT) applied. The source for everything in
this archive is in those two repositories. build.sh rebuilds the runner from them.
EOF

(cd "$OUT" && zip -qr "$ASSET" va11-hall-a-mac && shasum -a 256 "$ASSET" > "$ASSET.sha256")
cp "$HERE/install.sh" "$OUT/install.sh"

echo "Release files in $OUT:"
ls -l "$OUT" | sed 's/^/  /'
