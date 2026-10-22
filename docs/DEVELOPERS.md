# Developing

These notes are for working on the project itself: building the runner from source, the patches, the checks and how a
release is made. If you just want to play, the README is all you need.

## Building

The Xcode command line tools (`xcode-select --install`) are the only requirement:

```sh
git clone https://github.com/kecan0406/va11-hall-a-mac.git && cd va11-hall-a-mac
./build.sh                  # fetches Butterscotch, applies the patches, builds, then runs install.sh
./build.sh --universal      # arm64 + x86_64
./build.sh --build-only     # build into build/dist/ and stop
./release.sh                # the files a release is made of, in build/release/
```

Options `build.sh` doesn't know are handed to `install.sh`. Running `./install.sh` without `--runner` installs the
published release instead of your build.

## How it works

`build.sh` fetches Butterscotch at a pinned commit (`BUTTERSCOTCH_COMMIT` in `build.sh`), applies the patches in
`patches/` and builds the runner. `install.sh` wraps the runner in an app bundle with a small launcher and replaces one
file in the game's Steam folder so the Play button starts it. For achievements it copies Steam's own
`libsteam_api.dylib` into the app, so the release carries no Valve file.

| Patch | What it fixes |
|---|---|
| `0001` audio | Ogg files that carry a Theora video stream next to the Vorbis audio were silent; the patch hands the decoder only the Vorbis pages. |
| `0002` mouse | The cursor was mirrored vertically, and on Retina displays it ran up to twice the real position. |
| `0003` input recording | Records and replays the mouse, not just the keyboard. What the automatic checks use. |
| `0004` fullscreen | Implements the fullscreen functions the game's options menu uses. |
| `0005` room warp | Lets a recording jump into a room the game only enters through its own logic. Test aid only. |
| `0006` data files | Loads data files whose fonts and strings sit outside their own chunks, as fan translations built with font tools have. |
| `0007` achievements | Unlocks Steam achievements through the `libsteam_api.dylib` next to the runner. Without that file the game runs as before. |

These are fixes to Butterscotch, not to the game.

## Checks

```sh
tests/run.sh               # unit tests, no game needed
python3 verify/verify.py   # full checks, against a copy of the game
```

`tests/run.sh` covers the launcher (links, overrides, saves), the installer (install, undo, the Steam hook, packs) and
the scenario compiler. `verify.py` runs the scenarios in [SCENARIOS.md](SCENARIOS.md); what it measures and what it
leaves open are in [VERIFICATION.md](VERIFICATION.md).

## Releasing

Pushing a tag (`git tag v1.1.0 && git push origin v1.1.0`) runs the release workflow: it builds the universal runner,
runs the checks and attaches `va11-hall-a-mac.zip`, its checksum and `install.sh` to a GitHub release. The install line
in the README always fetches the latest one.
