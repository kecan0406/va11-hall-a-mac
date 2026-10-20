# Overrides: translations and other file replacements

The app reads the game from your Steam folder and never writes there (the optional Steam hook only swaps `Mac_Runner`,
see the README). To replace some of the game's files, for example
with a fan translation, put the replacements in the overrides folder:

```
~/Library/Application Support/VA-11 Hall-A/overrides/
```

Every launch rebuilds the game folder the runner sees: Steam's files first, then your overrides on top. Delete a file from
the overrides folder and the Steam original is back on the next launch.

## The easy way: a translation pack

Download the pack from the translators' own page, then run the installer with `--pack`:

```sh
curl -fsSL https://github.com/kecan0406/va11-hall-a-mac/releases/latest/download/install.sh | bash -s -- --pack
```

A window opens; choose the `.zip`, `.rar` or `.7z` file you downloaded. The installer opens it, finds the pack's
`data.win` and the language folders that the game has too (such as `scripts`), and puts them in `overrides/`. Files a Mac
doesn't need (Windows programs, readme files) are left out, and it says which. You can also give the file or an
unzipped folder: `... | bash -s -- --pack ~/Downloads/pack.rar`.

To go back to the original text: `... | bash -s -- --remove-pack`.

The rest of this page is what that does, for doing it by hand or for other kinds of replacements.

## Rules

- A file in `overrides/` replaces the Steam file with the same name.
- A **folder** in `overrides/` that also exists in Steam's `Contents/Resources` is merged one level deep: each item inside
  it replaces the Steam item with the same name, and the rest of Steam's items stay. A translation that ships
  `scripts/eng/` replaces Steam's `scripts/eng/`, while `scripts/jp/` and `scripts/chn/` still come from Steam.
- A file named `data.win` in `overrides/` becomes the game data the runner loads, instead of Steam's `game.ios`. Windows
  builds and most translation packs ship their data under this name.

## Example: a translation pack

A pack that contains `data.win` and `scripts/eng/...`:

```sh
mkdir -p ~/Library/Application\ Support/VA-11\ Hall-A/overrides
cp pack/data.win ~/Library/Application\ Support/VA-11\ Hall-A/overrides/
cp -R pack/scripts ~/Library/Application\ Support/VA-11\ Hall-A/overrides/
```

Start the app. Packs replace one of the three language entries; the text of the language shown on the first screen (for
example "English") is what the pack changed.

To go back to the original game, remove the files you added from `overrides/`, or run the installer with `--remove-pack`.

## Notes

- Check a pack before you use it. Data files run game code inside the runner, which can only touch the game's own save
  folder, but a pack is still someone else's work: take it from the translators' own page.
- Packs built for an older version of the game bring the old game with them: a data file replaces the whole game, so the
  version is the pack's, not Steam's.
- `python3 verify/verify.py --overrides <folder>` runs the automatic checks against a game with your overrides applied.
- The repository doesn't include or distribute any translation.
