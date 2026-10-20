#!/bin/bash
set -euo pipefail

REPO=kecan0406/va11-hall-a-mac
ASSET=va11-hall-a-mac.zip
APP_BASENAME="VA-11 Hall-A (native).app"
DATA_DIR_NAME="VA-11 Hall-A"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

APP_DIR="${VA11_APP_DIR:-$HOME/Applications}"
DATA_DIR="${VA11_DATA_DIR:-$HOME/Library/Application Support/$DATA_DIR_NAME}"
STEAM_RESOURCES="${VA11_STEAM_RESOURCES:-}"
RELEASE_BASE="${VA11_RELEASE_URL:-https://github.com/$REPO/releases/latest/download}"

RUNNER_SRC=""
LAUNCHER_SRC=""
INSTALLER_SRC=""
VERSION_TEXT=""
SCRIPT_DIR=""
TMP=""
MODE=install
HOOK=1
PACK_SRC=""
MAC_DESC=""

usage() {
  cat <<EOF
VA-11 Hall-A for Mac: installer

Usage: install.sh [options]

With no options it installs (or updates) the app and connects Steam's Play button.

  --no-steam-hook          install the app but leave Steam's files alone
  --steam-unhook           give Steam its original Mac_Runner back and keep the app
  --pack [FILE]            install a fan translation (.zip, .rar, .7z or a folder);
                           without FILE a window lets you choose the file
  --remove-pack            go back to the game's original text
  --uninstall              remove the app and the Play button connection (saves are kept)
  --doctor                 show what the installer sees on this Mac
  --app-dir DIR            install somewhere other than ~/Applications
  --steam-resources DIR    the game's Contents/Resources folder, if it isn't found automatically
  -h, --help               show this help

For developers:
  --runner FILE            use this runner binary instead of downloading the release (build.sh does this)
  --release-url URL        download the release files from URL instead of GitHub
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'Note: %s\n' "$*" >&2; }
step() { printf '\n[%s/%s] %s\n' "$1" "$2" "$3"; }

fail() {
  printf '\nStopped: %s\n' "$1" >&2
  shift
  while [ $# -gt 0 ]; do
    printf '  %s\n' "$1" >&2
    shift
  done
  exit 1
}

cleanup() {
  if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
}

ensure_tmp() {
  if [ -z "$TMP" ]; then TMP="$(mktemp -d)"; fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-steam-hook) HOOK=0 ;;
      --steam-unhook) MODE=unhook ;;
      --pack)
        MODE=pack
        if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then PACK_SRC="$2"; shift; fi ;;
      --remove-pack) MODE=remove_pack ;;
      --uninstall) MODE=uninstall ;;
      --doctor) MODE=doctor ;;
      --app-dir) [ $# -ge 2 ] || fail "--app-dir needs a folder"; APP_DIR="$2"; shift ;;
      --steam-resources) [ $# -ge 2 ] || fail "--steam-resources needs a folder"; STEAM_RESOURCES="$2"; shift ;;
      --runner) [ $# -ge 2 ] || fail "--runner needs a file"; RUNNER_SRC="$2"; shift ;;
      --release-url) [ $# -ge 2 ] || fail "--release-url needs a URL"; RELEASE_BASE="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; fail "I don't know the option $1" ;;
    esac
    shift
  done
  case "$APP_DIR" in /*) ;; *) APP_DIR="$PWD/$APP_DIR" ;; esac
  if [ "$APP_DIR" = "/" ]; then fail "--app-dir can't be the root folder"; fi
  APP="$APP_DIR/$APP_BASENAME"
  OVERRIDES="$DATA_DIR/overrides"
}

check_mac() {
  local version arch major minor ok=0
  version="${VA11_MACOS_VERSION:-$(sw_vers -productVersion)}"
  arch="${VA11_ARCH:-$(uname -m)}"
  major="${version%%.*}"
  case "$version" in *.*) minor="${version#*.}" ; minor="${minor%%.*}" ;; *) minor=0 ;; esac
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
  if [ "$arch" = arm64 ]; then
    if [ "$major" -ge 11 ]; then ok=1; fi
  elif [ "$major" -gt 10 ] || { [ "$major" -eq 10 ] && [ "$minor" -ge 15 ]; }; then
    ok=1
  fi
  [ "$ok" = 1 ] || fail "macOS $version is too old for this." \
    "It needs macOS 11 or newer on a Mac with Apple Silicon, or macOS 10.15 or newer on an Intel Mac."
  if [ "$arch" = arm64 ]; then MAC_DESC="macOS $version, Apple Silicon"; else MAC_DESC="macOS $version, Intel"; fi
}

steam_library_paths() {
  local vdf="$HOME/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
  [ -f "$vdf" ] || return 0
  sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)".*/\1/p' "$vdf"
}

find_steam_resources() {
  local library game
  while IFS= read -r library; do
    for game in "$library"/steamapps/common/"VA-11 HALL-A"/*.app/Contents/Resources/game.ios; do
      if [ -f "$game" ]; then dirname "$game"; return 0; fi
    done
  done < <(echo "$HOME/Library/Application Support/Steam"; steam_library_paths)
  return 1
}

resolve_game() {
  [ -n "$STEAM_RESOURCES" ] || STEAM_RESOURCES="$(find_steam_resources || true)"
  if [ -z "$STEAM_RESOURCES" ] || [ ! -f "$STEAM_RESOURCES/game.ios" ]; then
    fail "I can't find VA-11 Hall-A in Steam." \
      "1. Open Steam, find VA-11 Hall-A in your library and press Install." \
      "2. When it has finished downloading, run this again." \
      "If the game is somewhere unusual, add: --steam-resources \"<game folder>/<name>.app/Contents/Resources\""
  fi
}

download_release() {
  local expected actual payload
  ensure_tmp
  say "  Downloading from $RELEASE_BASE"
  curl -fL --retry 3 --progress-bar -o "$TMP/$ASSET" "$RELEASE_BASE/$ASSET" ||
    fail "I couldn't download the app." \
      "Check your internet connection and run this again." \
      "If it keeps failing, the project page may have moved: https://github.com/$REPO"
  curl -fsL --retry 3 -o "$TMP/$ASSET.sha256" "$RELEASE_BASE/$ASSET.sha256" ||
    fail "I couldn't download the file that checks the download." "Run this again in a minute."
  expected="$(awk '{print $1; exit}' "$TMP/$ASSET.sha256")"
  actual="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] ||
    fail "The download is damaged." "Run this again. Nothing was installed."
  unzip -q "$TMP/$ASSET" -d "$TMP/payload" || fail "I couldn't open the download." "Run this again."
  payload="$TMP/payload/va11-hall-a-mac"
  RUNNER_SRC="$payload/butterscotch"
  LAUNCHER_SRC="$payload/launcher.sh"
  INSTALLER_SRC="$payload/install.sh"
  VERSION_TEXT="$(cat "$payload/VERSION" 2>/dev/null || echo unknown)"
  [ -f "$RUNNER_SRC" ] && [ -f "$LAUNCHER_SRC" ] && [ -f "$INSTALLER_SRC" ] ||
    fail "The download is missing files." "Run this again, or tell the project page about it."
}

prepare_payload() {
  local source="${BASH_SOURCE[0]:-}"
  if [ -n "$source" ] && [ -f "$source" ]; then SCRIPT_DIR="$(cd "$(dirname "$source")" && pwd)"; fi
  if [ -n "$RUNNER_SRC" ]; then
    [ -f "$RUNNER_SRC" ] || fail "The runner file $RUNNER_SRC doesn't exist."
    [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/app/launcher.sh" ] ||
      fail "--runner only works from a copy of the repository."
    LAUNCHER_SRC="$SCRIPT_DIR/app/launcher.sh"
    INSTALLER_SRC="$SCRIPT_DIR/install.sh"
    VERSION_TEXT="${VA11_VERSION:-dev}"
  else
    [ -f "$SCRIPT_DIR/build.sh" ] &&
      warn "this is a copy of the repository, but the published release will be installed. Use ./build.sh for your local build."
    download_release
  fi
}

make_app() {
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$RUNNER_SRC" "$APP/Contents/MacOS/butterscotch"
  chmod 755 "$APP/Contents/MacOS/butterscotch"
  cp "$STEAM_RESOURCES/icon.icns" "$APP/Contents/Resources/icon.icns" || warn "the game's icon wasn't copied"
  cp "$INSTALLER_SRC" "$APP/Contents/Resources/install.sh"
  chmod 755 "$APP/Contents/Resources/install.sh"
  printf '%s\n' "$VERSION_TEXT" > "$APP/Contents/Resources/VERSION"

  local version_xml
  version_xml="$(printf '%s' "$VERSION_TEXT" | sed 's|&|\&amp;|g; s|<|\&lt;|g; s|>|\&gt;|g')"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>VA-11 Hall-A</string>
  <key>CFBundleDisplayName</key><string>VA-11 Hall-A</string>
  <key>CFBundleIdentifier</key><string>local.va11halla.butterscotch</string>
  <key>CFBundleExecutable</key><string>VA-11 Hall-A</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version_xml</string>
  <key>CFBundleVersion</key><string>$version_xml</string>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

  {
    echo '#!/bin/bash'
    printf 'STEAM_RES_DEFAULT=%q\n' "$STEAM_RESOURCES"
    printf 'DATA_DIR_NAME=%q\n' "$DATA_DIR_NAME"
    tail -n +2 "$LAUNCHER_SRC"
  } > "$APP/Contents/MacOS/VA-11 Hall-A"
  chmod 755 "$APP/Contents/MacOS/VA-11 Hall-A"

  xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || warn "the app couldn't be signed; it usually still runs"
}

steam_runner_path() { echo "$(dirname "$STEAM_RESOURCES")/MacOS/Mac_Runner"; }

is_hook() { [ -f "$1" ] && head -c 200 "$1" | grep -aq '^VA11_STEAM_HOOK=1$'; }

refresh_launch_services() {
  local bundle; bundle="$(dirname "$(dirname "$STEAM_RESOURCES")")"
  if [ -x "$LSREGISTER" ] && [ -f "$bundle/Contents/Info.plist" ]; then
    "$LSREGISTER" -f "$bundle" >/dev/null 2>&1 || true
  fi
}

steam_hook() {
  local launcher="$APP/Contents/MacOS/VA-11 Hall-A" runner tmp
  runner="$(steam_runner_path)"
  if [ ! -f "$runner" ]; then
    warn "Steam's game file isn't where I expected it: $runner"
    return 1
  fi
  tmp="$runner.hook-tmp"
  if ! is_hook "$runner"; then
    cp -p "$runner" "$runner.original" || { warn "I couldn't save Steam's original file."; return 1; }
  fi
  {
    echo '#!/bin/bash'
    echo 'VA11_STEAM_HOOK=1'
    printf 'LAUNCHER=%q\n' "$launcher"
    cat <<'SHIM'
if [ ! -x "$LAUNCHER" ]; then
  echo "VA-11 Hall-A: the app is missing." >&2
  if [ -z "${VA11_NO_DIALOG:-}" ]; then
    osascript -e 'display alert "VA-11 Hall-A" message "The app is missing. Running the installer again fixes it. To let Steam use its own file instead, run the installer with --steam-unhook."' >/dev/null 2>&1
  fi
  exit 1
fi
exec "$LAUNCHER" "$@"
SHIM
  } > "$tmp" || { warn "I couldn't write into Steam's folder. Check that Steam isn't running and try again."; rm -f "$tmp"; return 1; }
  chmod 755 "$tmp" && mv -f "$tmp" "$runner" || { warn "I couldn't change Steam's file."; rm -f "$tmp"; return 1; }
  refresh_launch_services
}

steam_unhook() {
  local runner; runner="$(steam_runner_path)"
  if ! is_hook "$runner"; then
    say "Steam's Play button isn't connected to the app; there's nothing to undo."
    return 0
  fi
  if [ ! -f "$runner.original" ]; then
    warn "Steam's original file is missing ($runner.original)."
    warn "In Steam: right-click the game > Properties > Installed Files > Verify integrity of game files."
    return 1
  fi
  mv -f "$runner.original" "$runner" || return 1
  refresh_launch_services
  say "Steam's own file is back."
}

choose_pack_file() {
  osascript -e 'POSIX path of (choose file with prompt "Choose the translation file you downloaded (.zip, .rar or .7z)")' 2>/dev/null ||
    fail "No file was chosen."
}

install_pack() {
  local source="$PACK_SRC" root data entry name installed="" ignored=""
  resolve_game
  if [ -z "$source" ]; then source="$(choose_pack_file)"; fi
  [ -e "$source" ] || fail "I can't find $source"
  ensure_tmp
  if [ -d "$source" ]; then
    root="$source"
  else
    mkdir -p "$TMP/pack"
    tar -xf "$source" -C "$TMP/pack" >/dev/null 2>&1 ||
      fail "I can't open $source." "Try a .zip, or unpack it in an app like Keka and install the folder: install.sh --pack <folder>"
    find "$TMP/pack" -type l -delete
    root="$TMP/pack"
  fi
  data="$(find "$root" -iname data.win -type f -not -path '*/__MACOSX/*' | head -1)"
  [ -n "$data" ] || fail "This doesn't look like a translation for this game: there is no data.win inside." \
    "Translations for the Windows version of VA-11 Hall-A work; other kinds of files don't."
  root="$(dirname "$data")"
  mkdir -p "$OVERRIDES"
  cp "$data" "$OVERRIDES/data.win"
  installed="data.win"
  for entry in "$root"/*; do
    name="${entry##*/}"
    [ "$entry" = "$data" ] && continue
    if [ -d "$entry" ] && [ -d "$STEAM_RESOURCES/$name" ]; then
      rm -rf "${OVERRIDES:?}/$name"
      cp -R "$entry" "$OVERRIDES/$name"
      installed="$installed, $name/"
    else
      ignored="$ignored $name"
    fi
  done
  find "$OVERRIDES" -name .DS_Store -delete
  say "Translation installed: $installed"
  if [ -n "$ignored" ]; then say "Left out (not needed on a Mac):$ignored"; fi
  say "Start the game as usual. The language you pick on the first screen shows the translated text."
  say "A translation brings its own version of the game with it. To go back to the original: install.sh --remove-pack"
}

remove_pack() {
  local entry name removed=0
  resolve_game
  if [ -e "$OVERRIDES/data.win" ]; then rm -f "$OVERRIDES/data.win"; removed=1; fi
  for entry in "$STEAM_RESOURCES"/*; do
    name="${entry##*/}"
    if [ -d "$entry" ] && [ -e "$OVERRIDES/$name" ]; then rm -rf "${OVERRIDES:?}/$name"; removed=1; fi
  done
  if [ "$removed" = 1 ]; then say "The translation is removed. The original text is back the next time you start the game."
  else say "There was no translation installed."
  fi
}

do_doctor() {
  local game runner state="n/a" app_state="not installed" pack="none"
  game="${STEAM_RESOURCES:-$(find_steam_resources || true)}"
  echo "macOS:         $(sw_vers -productVersion) ($(uname -m))"
  echo "Steam folder:  $HOME/Library/Application Support/Steam $([ -d "$HOME/Library/Application Support/Steam" ] && echo '(found)' || echo '(not found)')"
  echo "Libraries:     $(steam_library_paths | tr '\n' ' ')"
  echo "Game:          ${game:-NOT FOUND}"
  if [ -n "$game" ]; then
    runner="$(dirname "$game")/MacOS/Mac_Runner"
    if is_hook "$runner"; then state="connected (Play starts the app)"
    elif [ -f "$runner" ]; then state="not connected (Steam's own file: $(file -b "$runner" 2>/dev/null | cut -c1-40))"
    else state="Mac_Runner not found"
    fi
  fi
  if [ -x "$APP/Contents/MacOS/VA-11 Hall-A" ]; then
    app_state="installed, version $(cat "$APP/Contents/Resources/VERSION" 2>/dev/null || echo unknown)"
  fi
  if [ -e "$OVERRIDES/data.win" ]; then pack="installed (data.win in $OVERRIDES)"; fi
  echo "App:           $app_state ($APP)"
  echo "Play button:   $state"
  echo "Translation:   $pack"
  echo "Saves:         $DATA_DIR/saves"
  case "$app_state" in
    "not installed") echo "Next:          run the installer again to install the app." ;;
    installed*)
      if ! [ "$state" = "connected (Play starts the app)" ]; then
        echo "Next:          run the installer again to reconnect the Play button."
      fi ;;
  esac
}

do_install() {
  say "VA-11 Hall-A for Mac"
  step 1 4 "Checking your Mac"
  check_mac
  say "  OK: $MAC_DESC"
  step 2 4 "Looking for the game in Steam"
  resolve_game
  say "  Found it."
  step 3 4 "Installing the app"
  prepare_payload
  make_app
  say "  Installed: $APP"
  step 4 4 "Connecting Steam's Play button"
  local connected=0
  if [ "$HOOK" = 1 ]; then
    if steam_hook; then connected=1; say "  Done."; else warn "The Play button isn't connected. The app itself is installed."; fi
  else
    say "  Skipped, as you asked."
  fi
  echo
  say "All set."
  if [ "$connected" = 1 ]; then
    say "  Open Steam and press Play. You can also open \"VA-11 Hall-A (native)\" from ~/Applications or Spotlight."
  else
    say "  Open \"VA-11 Hall-A (native)\" from ~/Applications or Spotlight to play."
  fi
  say "  If the first Play opens an error, press Play again."
  say "  If Play stops working after Steam checks or updates the game, run the same installer again."
}

do_uninstall() {
  if [ -z "$STEAM_RESOURCES" ]; then STEAM_RESOURCES="$(find_steam_resources || true)"; fi
  if [ -n "$STEAM_RESOURCES" ]; then steam_unhook || true; fi
  if [ -d "$APP" ]; then
    rm -rf "$APP"
    say "The app is removed."
  else
    say "The app isn't installed."
  fi
  say "Your saves and translation files are still in: $DATA_DIR"
  say "Delete that folder too if you want everything gone."
}

main() {
  parse_args "$@"
  case "$MODE" in
    install) do_install ;;
    unhook) resolve_game; steam_unhook ;;
    pack) install_pack ;;
    remove_pack) remove_pack ;;
    uninstall) do_uninstall ;;
    doctor) do_doctor ;;
  esac
}

trap cleanup EXIT
main "$@" </dev/null
