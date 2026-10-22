#!/bin/bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$(dirname "$HERE")/app/launcher.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

STEAM="$WORK/steam/Resources"
DATA="$WORK/data"
OVERRIDES="$DATA/overrides"
mkdir -p "$STEAM/scripts/eng" "$STEAM/scripts/jp" "$STEAM/scripts/chn" "$STEAM/answer" "$STEAM/English.lproj" "$WORK/runner"
for f in game.ios options.ini icon.icns scripts/eng/a.txt scripts/jp/a.txt scripts/chn/a.txt answer/Her.png; do echo "$f" > "$STEAM/$f"; done
printf '[Mac]\r\nDisplayName="VA-11 Hall-A"\r\nSteamAppId="447530"\r\n' > "$STEAM/options.ini"

cat > "$WORK/runner/butterscotch" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$RUNNER_LOG"
printf '%s\n' "${SteamAppId-unset}" > "$RUNNER_LOG.appid"
EOF
chmod +x "$WORK/runner/butterscotch"

export VA11_STEAM_RESOURCES="$STEAM" VA11_DATA_DIR="$DATA" VA11_RUNNER="$WORK/runner/butterscotch" VA11_NO_DIALOG=1
export RUNNER_LOG="$WORK/runner.log"

failures=0
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}
launch() { "$LAUNCHER" "$@" >/dev/null 2>&1; }
steam_listing() { (cd "$STEAM" && find . | sort | shasum | cut -d' ' -f1); }

STEAM_BEFORE="$(steam_listing)"

launch --flag
check "plain run: runner gets the game file last" '[ "$(tail -1 "$RUNNER_LOG")" = "$DATA/game.ios" ]'
check "plain run: runner gets the extra argument first" '[ "$(head -1 "$RUNNER_LOG")" = "--flag" ]'
check "plain run: Steam files are linked" '[ -L "$DATA/game.ios" ] && [ -L "$DATA/scripts" ] && [ -L "$DATA/options.ini" ]'
check "plain run: Cocoa leftovers of the 32-bit runner are not linked" '[ ! -e "$DATA/English.lproj" ] && [ ! -e "$DATA/icon.icns" ]'

mkdir -p "$DATA/saves" && echo progress > "$DATA/saves/slot1.txt"
launch
check "second run: no link is created inside a linked folder" '[ ! -e "$DATA/scripts/scripts" ]'
check "second run: saves untouched" '[ "$(cat "$DATA/saves/slot1.txt")" = progress ]'

mkdir -p "$OVERRIDES/scripts/eng"
echo translated > "$OVERRIDES/scripts/eng/a.txt"
echo translated-data > "$OVERRIDES/data.win"
launch
check "override: data.win becomes the game file" '[ "$(tail -1 "$RUNNER_LOG")" = "$DATA/data.win" ]'
check "override: data.win is a link to the override" '[ "$(cat "$DATA/data.win")" = translated-data ]'
check "override: scripts is merged, not replaced" '[ -d "$DATA/scripts" ] && [ ! -L "$DATA/scripts" ]'
check "override: the overridden language comes from the override" '[ "$(cat "$DATA/scripts/eng/a.txt")" = translated ]'
check "override: the other languages still come from Steam" '[ "$(cat "$DATA/scripts/jp/a.txt")" = scripts/jp/a.txt ] && [ "$(cat "$DATA/scripts/chn/a.txt")" = scripts/chn/a.txt ]'
check "override: the Steam game.ios is still linked" '[ "$(cat "$DATA/game.ios")" = game.ios ]'

launch
check "override, second run: stable" '[ "$(cat "$DATA/scripts/eng/a.txt")" = translated ] && [ ! -e "$DATA/scripts/scripts" ] && [ "$(ls "$DATA/scripts" | wc -l | tr -d " ")" = 3 ]'
check "override: saves untouched" '[ "$(cat "$DATA/saves/slot1.txt")" = progress ]'

rm -rf "$OVERRIDES/scripts" "$OVERRIDES/data.win"
launch
check "override removed: back to the Steam game file" '[ "$(tail -1 "$RUNNER_LOG")" = "$DATA/game.ios" ]'
check "override removed: no stale data.win link" '[ ! -e "$DATA/data.win" ] && [ ! -L "$DATA/data.win" ]'
check "override removed: scripts is linked to Steam again" '[ -L "$DATA/scripts" ] && [ "$(cat "$DATA/scripts/eng/a.txt")" = scripts/eng/a.txt ]'

check "Steam app ID: taken from the game's options.ini" '[ "$(cat "$RUNNER_LOG.appid")" = 447530 ]'
check "Steam app ID: one already set is kept" 'SteamAppId=123 "$LAUNCHER" >/dev/null 2>&1; [ "$(cat "$RUNNER_LOG.appid")" = 123 ]'

check "prepare only: prints the game file and doesn't start the runner" '
  rm -f "$RUNNER_LOG"
  out="$(VA11_PREPARE_ONLY=1 "$LAUNCHER")"
  [ "$out" = "$DATA/game.ios" ] && [ ! -e "$RUNNER_LOG" ]'

check "Steam folder is never modified" '[ "$(steam_listing)" = "$STEAM_BEFORE" ]'

check "missing game: exits with an error" '! VA11_STEAM_RESOURCES="$WORK/nowhere" "$LAUNCHER" >/dev/null 2>&1'

[ "$failures" -eq 0 ] && echo "PASS" || { echo "FAILED ($failures)"; exit 1; }
