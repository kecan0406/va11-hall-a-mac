#!/bin/bash
STEAM_RES="${VA11_STEAM_RESOURCES:-${STEAM_RES_DEFAULT:-}}"
DATA_DIR_NAME="${DATA_DIR_NAME:-VA-11 Hall-A}"
DATA="${VA11_DATA_DIR:-$HOME/Library/Application Support/$DATA_DIR_NAME}"
OVERRIDES="${VA11_OVERRIDES:-$DATA/overrides}"
CONTENTS="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
RUNNER="${VA11_RUNNER:-$CONTENTS/MacOS/butterscotch}"

if [ ! -f "$STEAM_RES/game.ios" ]; then
  echo "game.ios not found in: $STEAM_RES" >&2
  if [ -z "${VA11_NO_DIALOG:-}" ]; then
    osascript -e 'display alert "VA-11 Hall-A" message "Could not find the game in Steam. Install VA-11 Hall-A in Steam, then run the installer again."' >/dev/null 2>&1
  fi
  exit 1
fi

mkdir -p "$DATA" "$OVERRIDES"

for entry in "$DATA"/*; do
  if [ -L "$entry" ] && [ ! -e "$entry" ]; then rm "$entry"; fi
done

for item in "$STEAM_RES"/*; do
  name="${item##*/}"
  case "$name" in English.lproj|icon.icns|saves|overrides) continue ;; esac
  [ -e "$OVERRIDES/$name" ] && continue
  if [ -d "$DATA/$name" ] && [ ! -L "$DATA/$name" ]; then
    rm -rf "$DATA/$name" || { echo "VA-11 Hall-A: couldn't replace the folder: $DATA/$name" >&2; continue; }
  fi
  ln -sfn "$item" "$DATA/$name"
done

for item in "$OVERRIDES"/*; do
  [ -e "$item" ] || continue
  name="${item##*/}"
  if [ -d "$item" ] && [ -d "$STEAM_RES/$name" ]; then
    [ -L "$DATA/$name" ] && rm "$DATA/$name"
    mkdir -p "$DATA/$name"
    for child in "$DATA/$name"/*; do
      [ -L "$child" ] && rm "$child"
    done
    for child in "$STEAM_RES/$name"/*; do
      [ -e "$item/${child##*/}" ] && continue
      ln -sfn "$child" "$DATA/$name/${child##*/}"
    done
    for child in "$item"/*; do
      [ -e "$child" ] && ln -sfn "$child" "$DATA/$name/${child##*/}"
    done
  else
    ln -sfn "$item" "$DATA/$name"
  fi
done

GAME="$DATA/game.ios"
[ -e "$OVERRIDES/data.win" ] && GAME="$DATA/data.win"

if [ -n "${VA11_PREPARE_ONLY:-}" ]; then
  echo "$GAME"
  exit 0
fi

# Steam records achievements for the app ID in SteamAppId. Unless whoever started the app set it, it comes from the
# game's options.ini (SteamAppId="447530", with Windows line endings).
if [ -z "${SteamAppId:-}" ]; then
  SteamAppId="$(tr -d '\r"' < "$STEAM_RES/options.ini" 2>/dev/null | sed -n 's/^SteamAppId=\([0-9][0-9]*\)$/\1/p' | head -1)"
  [ -n "$SteamAppId" ] && export SteamAppId
fi

exec -a "VA-11 Hall-A" "$RUNNER" "$@" "$GAME"
