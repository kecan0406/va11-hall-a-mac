#!/bin/bash
set -euo pipefail

BUTTERSCOTCH_REPO=https://github.com/ButterscotchRunner/Butterscotch.git
BUTTERSCOTCH_COMMIT=54e10ec4e4a5713130675c7719dda7c437b4f849

TARGET_ARM64=11.0
TARGET_X86_64=10.15

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/build"
SRC="$WORK/butterscotch"
DIST="$WORK/dist"

UNIVERSAL=0
BUILD_ONLY=0
INSTALL_ARGS=()

usage() {
  cat <<EOF
Usage: ./build.sh [options]

Builds the runner from source, then installs it with install.sh. This needs the Xcode command line tools.
If you only want to play, you don't need this: use install.sh, which downloads a ready-made runner.

  --universal       build arm64 + x86_64 (default: this Mac's architecture only)
  --build-only      build the runner into build/dist/ and stop
  -h, --help        show this help

Any other option is passed on to install.sh (see ./install.sh --help).
EOF
}

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --universal) UNIVERSAL=1 ;;
    --build-only) BUILD_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) INSTALL_ARGS+=("$1") ;;
  esac
  shift
done
if [ "$BUILD_ONLY" = 1 ] && [ "${#INSTALL_ARGS[@]}" -gt 0 ]; then
  die "--build-only stops before install.sh runs, so its options would be ignored: ${INSTALL_ARGS[*]} (drop --build-only, or run install.sh separately)"
fi

require_toolchain() {
  xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools are missing. Install them with: xcode-select --install"
  for tool in git make cc lipo codesign; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' not found. Try: xcode-select --install"
  done
  xcrun --show-sdk-path >/dev/null 2>&1 || die "no macOS SDK found. Try: xcode-select --install"
}

fetch_and_patch() {
  mkdir -p "$WORK"
  if [ ! -d "$SRC/.git" ]; then
    git init -q "$SRC"
    git -C "$SRC" remote add origin "$BUTTERSCOTCH_REPO"
  fi
  git -C "$SRC" fetch -q --depth 1 origin "$BUTTERSCOTCH_COMMIT" || die "couldn't fetch Butterscotch (network?)"
  git -C "$SRC" checkout -q --force FETCH_HEAD
  git -C "$SRC" clean -fdxq
  for patch in "$HERE"/patches/*.patch; do
    git -C "$SRC" apply "$patch" || die "patch $(basename "$patch") doesn't apply"
  done
}

build_slice() {
  local arch="$1" target="$2" log="$WORK/build-$1.log"
  echo "Building runner ($arch, macOS $target+)..."
  rm -rf "$SRC/build" "$SRC/compat/config.mk" "$SRC"/compat/tmp/*
  if ! THREADS=1 MACOSX_DEPLOYMENT_TARGET="$target" make -C "$SRC" -j"$(sysctl -n hw.ncpu)" \
        CC="cc -arch $arch" BACKEND=appkit VIDEO_BACKEND=none >"$log" 2>&1; then
    tail -30 "$log" >&2
    die "runner build failed for $arch (full log: $log)"
  fi
  mkdir -p "$DIST"
  cp "$SRC/build/butterscotch" "$DIST/butterscotch-$arch"
}

build_runner() {
  local archs
  if [ "$UNIVERSAL" = 1 ]; then archs="arm64 x86_64"; else archs="$(uname -m)"; fi

  fetch_and_patch
  rm -rf "$DIST"
  for arch in $archs; do
    case "$arch" in
      arm64) build_slice arm64 "$TARGET_ARM64" ;;
      x86_64) build_slice x86_64 "$TARGET_X86_64" ;;
      *) die "unsupported architecture: $arch" ;;
    esac
  done

  lipo -create $(for arch in $archs; do echo "$DIST/butterscotch-$arch"; done) -output "$DIST/butterscotch"
  echo "Runner: $DIST/butterscotch ($(lipo -archs "$DIST/butterscotch"))"
}

require_toolchain
build_runner

if [ "$BUILD_ONLY" = 1 ]; then exit 0; fi

exec "$HERE/install.sh" --runner "$DIST/butterscotch" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
