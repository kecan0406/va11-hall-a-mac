# VA-11 Hall-A for Mac

Play **VA-11 Hall-A: Cyberpunk Bartender Action** on current Macs, including Apple Silicon.

Steam's Mac version of the game is 32-bit, and macOS 10.15 and later can't run 32-bit programs, so pressing Play does
nothing useful. This project puts a small, current app on your Mac and connects Steam's Play button to it. The game
itself comes from your own Steam copy.

## Install

You need the game installed in Steam first. Then:

1. Open **Terminal**: press `Cmd` + `Space`, type `Terminal`, press `Return`.
2. Paste this line and press `Return`:

   ```sh
   curl -fsSL https://github.com/kecan0406/va11-hall-a-mac/releases/latest/download/install.sh | bash
   ```

3. When it says "All set", go back to Steam and press **Play**.

It takes about a minute and needs nothing else installed: no developer tools, no Rosetta.

What the line does:

- It downloads a ready-made app (about 2 MB), checks the download, and puts it in `~/Applications`.
- It replaces one file in the game's Steam folder, `Mac_Runner`, with a few lines that start the app. Steam's original
  file is kept next to it as `Mac_Runner.original`. Nothing else in the Steam folder changes, and no game files are copied.
- Your saves and settings go to `~/Library/Application Support/VA-11 Hall-A/`.

It works on macOS 11 or newer on Apple Silicon, and macOS 10.15 or newer on Intel Macs.

### When something goes wrong

| What you see | What to do |
|---|---|
| "I can't find VA-11 Hall-A in Steam" | Install the game in Steam, wait for the download to finish, run the line again. |
| Play stops working after Steam "Verify integrity of game files" or after the game updates | Steam put its own file back. Run the same line again. |
| The first Play after installing shows an error | Press Play again. |

### Other things you can do

Add the options after `bash -s --`:

```sh
curl -fsSL https://github.com/kecan0406/va11-hall-a-mac/releases/latest/download/install.sh | bash -s -- --doctor
```

| Option | What it does |
|---|---|
| `--pack` | install a fan translation. A window opens to choose the file you downloaded (`.zip`, `.rar` or `.7z`). You can also give the file or folder after it. See [docs/MODS.md](docs/MODS.md). |
| `--remove-pack` | go back to the game's original text |
| `--no-steam-hook` | install the app but leave the game's Steam folder alone; open the app from `~/Applications` or Spotlight instead |
| `--steam-unhook` | give Steam its original `Mac_Runner` back and keep the app |
| `--uninstall` | remove the app and the Play button connection. Your saves stay. |
| `--doctor` | show what the installer sees: macOS, Steam, the game, the app and the Play button |
| `--app-dir DIR` | install somewhere other than `~/Applications` |
| `--steam-resources DIR` | the game's `Contents/Resources` folder, if the installer can't find it |

To update the app to a newer version, run the install line again.

## What works, and what doesn't

- Native on Apple Silicon and Intel. Alt+Enter and the options menu switch fullscreen.
- Steam sees the game as running, so Play turns into Stop and the last-played time updates.
- Steam achievements, the Steam overlay and cloud saves don't work: the app doesn't talk to Steam.
- F12 doesn't save a screenshot.
- Rendering uses the system's OpenGL, which Apple has deprecated but still ships. If a future macOS removes it, the
  runner will need another backend.
- The drink-mixing minigame, sound output and the Japanese and Chinese texts are covered by the
  [manual checklist](docs/QA_CHECKLIST.md), not by automatic tests.

## How it works

The app wraps the Butterscotch runner with a small launcher, and the installer replaces one file in the game's Steam
folder so that Play starts it. The patches that make the game run on a Mac, and the build tooling and checks, are in
[docs/DEVELOPERS.md](docs/DEVELOPERS.md).

## Does it work? Checking, not claiming

There is no 64-bit reference runner to compare against, so "100% compatible" can't be proven. What can be measured is in
[docs/VERIFICATION.md](docs/VERIFICATION.md), with the pass criteria fixed beforehand:

```sh
tests/run.sh               # unit tests, no game needed
python3 verify/verify.py   # checks against your copy of the game (opens the game window for a few minutes)
```

## License

[AGPL-3.0](LICENSE). The patches derive from Butterscotch, which is AGPL-3.0, so this repository is too.

VA-11 Hall-A is by Sukeban Games, published by Ysbryd Games. This project isn't affiliated with them and contains none of
their work.
