#!/bin/bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
INSTALL="$REPO/install.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BUNDLE="$WORK/steam/steamapps/common/VA-11 HALL-A/Fake Game.app/Contents"
RESOURCES="$BUNDLE/Resources"
RUNNER="$BUNDLE/MacOS/Mac_Runner"
APP_DIR="$WORK/it's here/Applications"
APP="$APP_DIR/VA-11 Hall-A (native).app"
DATA="$WORK/data"
FAKE_RUNNER="$WORK/fake_butterscotch"

mkdir -p "$RESOURCES/scripts/eng" "$RESOURCES/scripts/jp" "$RESOURCES/answer" "$BUNDLE/MacOS"
for f in game.ios icon.icns options.ini scripts/eng/a.txt scripts/jp/a.txt answer/x.png; do echo "$f" > "$RESOURCES/$f"; done
printf 'original runner v1\n' > "$RUNNER"
chmod 755 "$RUNNER"
cat > "$FAKE_RUNNER" <<'EOF'
#!/bin/bash
{ echo "pid=$$"; printf 'arg=%s\n' "$@"; } > "$RUNNER_LOG"
EOF
chmod 755 "$FAKE_RUNNER"

export VA11_STEAM_RESOURCES="$RESOURCES" VA11_APP_DIR="$APP_DIR" VA11_DATA_DIR="$DATA" VA11_NO_DIALOG=1
export RUNNER_LOG="$WORK/runner.log"

failures=0
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}
steam_listing() { (cd "$BUNDLE" && find . -type f | sort | xargs shasum | shasum | cut -d' ' -f1); }
steam_listing_without_runner() { (cd "$BUNDLE" && find . -type f -not -name 'Mac_Runner*' | sort | xargs shasum | shasum | cut -d' ' -f1); }
hooked() { head -c 200 "$RUNNER" | grep -aq '^VA11_STEAM_HOOK=1$'; }
install() { "$INSTALL" --runner "$FAKE_RUNNER" "$@"; }

BEFORE_WITHOUT_RUNNER="$(steam_listing_without_runner)"

echo "== checks before anything is installed"
check "macOS too old for Apple Silicon: stops with a clear message" '
  out="$(VA11_MACOS_VERSION=10.15 VA11_ARCH=arm64 install 2>&1)"; rc=$?
  [ $rc -ne 0 ] && echo "$out" | grep -q "too old" && echo "$out" | grep -q "macOS 11" && [ ! -e "$APP" ]'
check "macOS 10.14 on Intel: stops with a clear message" '! VA11_MACOS_VERSION=10.14.6 VA11_ARCH=x86_64 install >/dev/null 2>&1 && [ ! -e "$APP" ]'
check "macOS 10.15 on Intel is accepted" 'VA11_MACOS_VERSION=10.15.7 VA11_ARCH=x86_64 install >/dev/null 2>&1 && [ -d "$APP" ]'
rm -rf "$APP"
check "game not installed: tells the user what to do" '
  out="$(HOME="$WORK/empty-home" VA11_STEAM_RESOURCES= install 2>&1)"; rc=$?
  [ $rc -ne 0 ] && echo "$out" | grep -q "open Steam\|Open Steam" && echo "$out" | grep -q "press Install" && [ ! -e "$APP" ]'

echo "== install"
install >"$WORK/install.out" 2>&1
check "install: finishes and says what to do next" 'grep -q "All set" "$WORK/install.out" && grep -q "press Play" "$WORK/install.out"'
check "install: the app has its launcher, runner, icon and version" '
  [ -x "$APP/Contents/MacOS/VA-11 Hall-A" ] && [ -x "$APP/Contents/MacOS/butterscotch" ] && [ -f "$APP/Contents/Resources/icon.icns" ] && [ "$(cat "$APP/Contents/Resources/VERSION")" = dev ]'
check "install: Info.plist is valid" 'plutil -lint "$APP/Contents/Info.plist" >/dev/null'
check "install: the app is signed" 'codesign --verify "$APP" 2>/dev/null'
check "install: the app starts the runner with the game file" '
  VA11_PREPARE_ONLY=1 "$APP/Contents/MacOS/VA-11 Hall-A" | grep -qx "$DATA/game.ios"'
check "install: Steam's Mac_Runner is now the hook, the original is kept" 'hooked && [ -x "$RUNNER" ] && [ "$(cat "$RUNNER.original")" = "original runner v1" ]'
check "install: nothing else in the Steam folder changed" '
  [ "$(steam_listing_without_runner)" = "$BEFORE_WITHOUT_RUNNER" ] && [ "$(ls "$BUNDLE/MacOS" | tr "\n" " ")" = "Mac_Runner Mac_Runner.original " ]'
check "install: the translation app is created for drag & drop installs" '
  DROPLET="$APP_DIR/VA-11 Hall-A Install Translation.app"; exe="$(plutil -extract CFBundleExecutable raw "$DROPLET/Contents/Info.plist" 2>/dev/null)"; [ -n "$exe" ] && [ -x "$DROPLET/Contents/MacOS/$exe" ]'

echo "== Play button"
bash -c 'echo $$ > "$0.pid"; exec "$0" --from-steam "two words"' "$RUNNER"
check "Play: Steam's file starts the runner with the game file and the arguments" '
  grep -qx "arg=--from-steam" "$RUNNER_LOG" && grep -qx "arg=two words" "$RUNNER_LOG" && [ "$(tail -1 "$RUNNER_LOG")" = "arg=$DATA/game.ios" ]'
check "Play: it is the same process all the way down, so Steam keeps watching it" '[ "$(cat "$RUNNER.pid")" = "$(sed -n "s/^pid=//p" "$RUNNER_LOG")" ]'
rm -f "$RUNNER.pid"

echo "== running the installer again"
install >/dev/null 2>&1
check "again: the backup is still Steam's original" '[ "$(cat "$RUNNER.original")" = "original runner v1" ] && hooked'
printf 'original runner v2\n' > "$RUNNER"
install >/dev/null 2>&1
check "again after Steam restored its file: connected again, backup refreshed" 'hooked && [ "$(cat "$RUNNER.original")" = "original runner v2" ]'
mkdir -p "$DATA/saves" && echo progress > "$DATA/saves/slot1.txt"
install >/dev/null 2>&1
check "again: saves untouched" '[ "$(cat "$DATA/saves/slot1.txt")" = progress ]'

mv "$APP/Contents/MacOS/VA-11 Hall-A" "$WORK/launcher.gone"
check "app missing when Play is pressed: exits with an error" '! "$RUNNER" >/dev/null 2>&1'
mv "$WORK/launcher.gone" "$APP/Contents/MacOS/VA-11 Hall-A"

echo "== undo"
"$INSTALL" --uninstall >/dev/null 2>&1
check "uninstall: removes the app, restores Steam's file, keeps the saves" '
  [ ! -e "$APP" ] && [ "$(cat "$RUNNER")" = "original runner v2" ] && [ ! -e "$RUNNER.original" ] && [ "$(cat "$DATA/saves/slot1.txt")" = progress ]'
check "uninstall: the translation app is gone too" '
  [ ! -e "$APP_DIR/VA-11 Hall-A Install Translation.app" ]'
check "uninstall again: nothing left to remove, Steam stays untouched" '
  b="$(steam_listing)"; "$INSTALL" --uninstall >/dev/null 2>&1 && [ "$(steam_listing)" = "$b" ]'

echo "== translation packs"
install >/dev/null 2>&1
PACK="$WORK/pack"
mkdir -p "$PACK/Some Pack V4/scripts/eng" "$PACK/Some Pack V4/windows_only" "$PACK/__MACOSX"
echo translated-data > "$PACK/Some Pack V4/data.win"
echo translated > "$PACK/Some Pack V4/scripts/eng/a.txt"
echo noise > "$PACK/Some Pack V4/scripts/.DS_Store"
echo readme > "$PACK/Some Pack V4/readme.txt"
echo exe > "$PACK/Some Pack V4/game.exe"
echo junk > "$PACK/__MACOSX/._data.win"
ln -s /etc/hosts "$PACK/Some Pack V4/scripts/eng/link"
(cd "$PACK" && zip -qry "$WORK/pack.zip" .)

"$INSTALL" --pack "$WORK/pack.zip" >"$WORK/pack.out" 2>&1
check "pack: data.win and the language folders are installed" '
  [ "$(cat "$DATA/overrides/data.win")" = translated-data ] && [ "$(cat "$DATA/overrides/scripts/eng/a.txt")" = translated ]'
check "pack: files a Mac does not need are left out and said so" '
  [ ! -e "$DATA/overrides/readme.txt" ] && [ ! -e "$DATA/overrides/game.exe" ] && [ ! -e "$DATA/overrides/windows_only" ] && grep -q "Left out" "$WORK/pack.out"'
check "pack: no archive junk and no symbolic links" '
  [ ! -e "$DATA/overrides/__MACOSX" ] && [ ! -e "$DATA/overrides/scripts/.DS_Store" ] && [ -z "$(find "$DATA/overrides" -type l)" ]'
check "pack: the app now loads the pack's data and keeps Steam's other languages" '
  [ "$(VA11_PREPARE_ONLY=1 "$APP/Contents/MacOS/VA-11 Hall-A")" = "$DATA/data.win" ] && [ "$(cat "$DATA/scripts/jp/a.txt")" = scripts/jp/a.txt ]'
check "pack: Steam files are untouched" '[ "$(ls "$RESOURCES" | tr "\n" " ")" = "answer game.ios icon.icns options.ini scripts " ]'

check "pack from a folder works too" '
  rm -rf "$DATA/overrides"; "$INSTALL" --pack "$PACK/Some Pack V4" >/dev/null 2>&1 && [ "$(cat "$DATA/overrides/data.win")" = translated-data ]'
check "pack: a file that is not a translation is refused and nothing changes" '
  echo hi > "$WORK/notes.txt"; (cd "$WORK" && zip -q notes.zip notes.txt)
  b="$(cat "$DATA/overrides/data.win")"; ! "$INSTALL" --pack "$WORK/notes.zip" >"$WORK/bad.out" 2>&1 && grep -q "no data.win" "$WORK/bad.out" && [ "$(cat "$DATA/overrides/data.win")" = "$b" ]'
check "pack: a file that cannot be opened is refused with advice" '! "$INSTALL" --pack "$WORK/notes.txt" >"$WORK/bad2.out" 2>&1 && grep -q "can.t open" "$WORK/bad2.out"'
check "pack: a missing file is refused" '! "$INSTALL" --pack "$WORK/nope.zip" >/dev/null 2>&1'

"$INSTALL" --remove-pack >/dev/null 2>&1
check "remove-pack: the original game is back, saves kept" '
  [ ! -e "$DATA/overrides/data.win" ] && [ ! -e "$DATA/overrides/scripts" ] && [ "$(VA11_PREPARE_ONLY=1 "$APP/Contents/MacOS/VA-11 Hall-A")" = "$DATA/game.ios" ] && [ "$(cat "$DATA/saves/slot1.txt")" = progress ]'
check "remove-pack when there is none: succeeds" '"$INSTALL" --remove-pack 2>&1 | grep -q "no translation"'
"$INSTALL" --uninstall >/dev/null 2>&1

echo "== the installer asks about a fan translation by itself"
# expect talks to the prompt the way a real typist does: it waits for the "> "
# prompt, sends the answer, and the pty stays alive until the installer exits.
run_ask() {
  VA11_I="$INSTALL" VA11_F="$FAKE_RUNNER" expect "$WORK/ask.expect" "$1" > "$WORK/ask.log" 2>&1
}
cat > "$WORK/ask.expect" <<'EXPECT'
set timeout 90
log_user 1
unset -nocomplain env(VA11_NO_DIALOG)
spawn /bin/bash $env(VA11_I) --runner $env(VA11_F)
set answer [lindex $argv 0]
expect {
  -re {> } { send -- "$answer\r"; expect eof }
  -re {All set} { }
  eof {}
}
exit 0
EXPECT
check "ask: an empty answer skips and the game stays original" '
  run_ask "" && grep -q "All set" "$WORK/ask.log" && ! [ -e "$DATA/overrides/data.win" ]'
check "ask: a pack dragged into the prompt is installed" '
  run_ask "$WORK/pack.zip" && [ "$(cat "$DATA/overrides/data.win")" = translated-data ]'
check "ask: a pack already installed is kept and the prompt does not re-ask" '
  run_ask "" && grep -q "already installed" "$WORK/ask.log"'
"$INSTALL" --remove-pack >/dev/null 2>&1
check "ask: without a Terminal session the question is skipped" '
  install >"$WORK/np.out" 2>&1 && grep -q "Translation: skipped" "$WORK/np.out"'
"$INSTALL" --remove-pack >/dev/null 2>&1

echo "== downloading the release"
REL="$WORK/release"
STAGE="$REL/va11-hall-a-mac"
mkdir -p "$STAGE" "$WORK/standalone"
cp "$FAKE_RUNNER" "$STAGE/butterscotch"
cp "$REPO/app/launcher.sh" "$STAGE/launcher.sh"
cp "$INSTALL" "$STAGE/install.sh"
echo "9.9.9" > "$STAGE/VERSION"
(cd "$REL" && zip -qr va11-hall-a-mac.zip va11-hall-a-mac && shasum -a 256 va11-hall-a-mac.zip > va11-hall-a-mac.zip.sha256)
cp "$INSTALL" "$WORK/standalone/install.sh"

(cd "$WORK/standalone" && ./install.sh --release-url "file://$REL" >"$WORK/dl.out" 2>&1)
check "download: installs from the release files" '[ -x "$APP/Contents/MacOS/butterscotch" ] && [ "$(cat "$APP/Contents/Resources/VERSION")" = 9.9.9 ] && hooked'
check "download: the app carries the installer for later use" 'cmp -s "$APP/Contents/Resources/install.sh" "$INSTALL"'
"$INSTALL" --uninstall >/dev/null 2>&1

cat "$INSTALL" | bash -s -- --release-url "file://$REL" >"$WORK/pipe.out" 2>&1
check "download: works when the installer is piped into bash, like curl | bash" 'grep -q "All set" "$WORK/pipe.out" && [ -d "$APP" ] && hooked'
"$INSTALL" --uninstall >/dev/null 2>&1

printf '%064d  va11-hall-a-mac.zip\n' 0 > "$REL/va11-hall-a-mac.zip.sha256"
check "download: a damaged file is refused and nothing is installed" '! "$INSTALL" --release-url "file://$REL" >"$WORK/bad3.out" 2>&1 && grep -q "damaged" "$WORK/bad3.out" && [ ! -e "$APP" ] && ! hooked'
check "download: an unreachable release says so" '! "$INSTALL" --release-url "file://$WORK/nowhere" >"$WORK/bad4.out" 2>&1 && grep -q "couldn.t download" "$WORK/bad4.out" && [ ! -e "$APP" ]'

echo "== only tools every Mac has"
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
for t in awk basename cat chmod codesign cp curl cut dirname file find grep head ls mkdir mktemp mv osacompile osascript plutil rm sed shasum sw_vers tail tar tr uname unzip xattr xargs sort; do
  ln -s "$(command -v $t)" "$TOOLS/$t"
done
for t in git make cc lipo gcc clang xcrun; do
  check "tools: $t is not available in this check" '[ ! -e "$TOOLS/$t" ]'
done
printf '%s  va11-hall-a-mac.zip\n' "$(cd "$REL" && shasum -a 256 va11-hall-a-mac.zip | cut -d' ' -f1)" > "$REL/va11-hall-a-mac.zip.sha256"
AFTER_UNINSTALL="$(steam_listing)"
(cd "$WORK/standalone" && env -i HOME="$WORK/home" PATH="$TOOLS" VA11_APP_DIR="$APP_DIR" VA11_DATA_DIR="$DATA" VA11_STEAM_RESOURCES="$RESOURCES" VA11_NO_DIALOG=1 \
  /bin/bash -c 'cat ./install.sh | /bin/bash -s -- --release-url "file://'"$REL"'"' >"$WORK/tools.out" 2>&1)
check "tools: a full install works with only those" 'grep -q "All set" "$WORK/tools.out" && ! grep -qi "command not found" "$WORK/tools.out" && hooked'
check "tools: the installed app starts with only those" '
  env -i HOME="$WORK/home" PATH="$TOOLS" VA11_NO_DIALOG=1 VA11_DATA_DIR="$DATA" VA11_PREPARE_ONLY=1 /bin/bash "$APP/Contents/MacOS/VA-11 Hall-A" 2>&1 | grep -qx "$DATA/game.ios"'

echo "== doctor"
check "doctor: reports app, Play button and translation" '
  out="$("$INSTALL" --doctor 2>&1)"; echo "$out" | grep -q "App: *installed, version 9.9.9" && echo "$out" | grep -q "Play button: *connected" && echo "$out" | grep -q "Translation: *none"'

"$INSTALL" --uninstall >/dev/null 2>&1
check "in the end the Steam folder is exactly as it was" '[ "$(steam_listing)" = "$AFTER_UNINSTALL" ]'

[ "$failures" -eq 0 ] && echo "PASS" || { echo "FAILED ($failures)"; exit 1; }
