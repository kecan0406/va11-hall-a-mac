# Verification

## The claim, and what can't be claimed

"Compatible" here means: for the game files Steam ships, this app does what the original runner does for everything a
player can reach, except the gaps listed in the README.

That can't be proven. The only runner that defines correct behaviour is the original, and it doesn't run on a 64-bit
Mac. Testing by comparison needs it, and a game this size has far too many states to check by hand. So this project does
the next best thing: it breaks the claim into parts that can be measured, fixes the pass criteria before running
anything, and keeps every check repeatable by anyone with a copy of the game. What the checks leave open is listed
at the end instead of being rounded up to "works".

```sh
tests/run.sh               # unit tests, no game needed (also run by CI)
python3 verify/verify.py   # everything below, against your copy of the game
```

`verify.py` opens the game window for a few minutes and runs in a throwaway copy of the save folder, so your saves are
never touched. Its report lands in `verify/report/latest/report.md`.

## What is checked

Each row is a claim, how it is measured, and the criterion that decides pass or fail. The criteria are in
`verify/verify.py` and were set before the numbers below were produced.

| Layer | Claim | Measured by | Pass when |
|---|---|---|---|
| Static coverage | The runner implements what the game calls | Disassemble the whole game, list every function it references, compare with what the runner implements | Every unimplemented function that a game event can reach is listed in `verify/allowlist.json` with its player-visible effect |
| Audio | Every sound plays | Decode all embedded sounds with the runner's own code path | All decode to non-silent audio |
| Smoke | The game runs without errors | Scripted play, then scan the runner's log | Exit code 0, no error line, no warning outside the allowlist |
| Rooms | Every room loads and runs | Walk the room order, jump into the rest | The expected rooms are entered |
| Golden path | A real game works from the title screen on | Replay a mouse-only session: the game's opening, to the first shift | The expected room sequence, in order |
| Determinism | Results don't depend on timing or luck | Replay every scenario twice | Same rooms and byte-identical screenshots |
| Regression | Nothing changed since the last known-good state | Screenshot hashes against a baseline recorded on this Mac | Equal (when a baseline exists for this Mac and runner build) |
| Input | Recording and replay agree | Replay a click while re-recording it | Same mouse events on the same frames |

The unit tests under `tests/` cover the pieces that are easy to get wrong: the launcher (links, overrides, saves, the
Steam folder staying untouched), the Ogg demuxer on synthetic files (mixed, plain, truncated, garbage), the mouse mapping
on 1x and 2x displays, and the scenario compiler. Scenarios are described in [SCENARIOS.md](SCENARIOS.md).

### Results, on the machine that built this

Apple Silicon, macOS 27.2, runner built from Butterscotch `54e10ec` plus the patches in `patches/`.

- **Static coverage**: the game references 443 functions; 419 are implemented (94.6%), which covers 98.7% of the call
  sites (14,212 of 14,393). Of the 24 that aren't, 18 have no static path from any game event (dead code in the game's
  bundled file-system library). The other 6 are known and explained: Steam achievements (`steam_get_achievement`,
  `steam_set_achievement`), the F12 screenshot (`screen_save`, `steam_send_screenshot`), and two one-time startup calls
  (`FS_set_gm_save_area`, `FS_set_working_directory`).
- **Audio**: 120 of 120 sounds decode. 32 of them (27%) are Ogg files with a video stream mixed in; **without patch 0001
  all 32 fail** (checked with the same harness and the demuxer bypassed).
- **Mouse**: with the old code the hand cursor drew at `(322, 602)` when the real cursor was at game position
  `(300, 200)`, where `(622, 482)` is correct (mirrored and at half scale). With patch 0002 it draws at `(622, 482)`.
  The unit test fails 10 of 10 checks without the patch and passes 10 of 10 with it.
- **Rooms**: all 46 rooms are entered and run without errors: 31 by walking the room order and the golden path, the other
  15 (game over, shooting minigame, loading screens, ...) by jumping into them.
- **Golden path**: the game's opening, played through to the first shift. 10 room changes, in the expected order.
- **Determinism**: every scenario, replayed twice, gives identical room sequences and byte-identical screenshots.
- **Input round trip**: replaying a click while recording gives back the same events on the same frames.
- **A translated game** (a fan translation from April 2017 that replaces `data.win` and `scripts/eng`, applied through
  `overrides/`): the runner could not load it at all before patch 0006 (the font parser read garbage kerning counts, then
  string pointers outside the string chunk crashed it). With the patch every check passes on it as well: 302 functions
  referenced, 276 implemented (98.6% of call sites), 120 of 120 sounds decode, the golden path takes the same 10 room
  changes, all 45 rooms of that older version are entered, and replays are identical. It is an older build of the game,
  so the numbers differ from the Steam version's.
- **Steam's Play button** (connected by the installer): Steam's log showed the original `Mac_Runner` failing with
  `OS Error 86` (bad CPU type). With the hook, `steam://run/447530`, the URL behind Play and behind the shortcut Steam
  puts in `~/Applications`, started the game in 7 of 8 launches. Steam logged the game process as added and, after it
  quit, as removed, and the game's last-played time moved to the last launch. The one failure came on the first launch
  right after the hook was installed (`OS Error 256`, LaunchServices `-10669`) and did not come back in 7 further
  attempts, including 2 that repeated the same sequence (failed Play, hook, Play). The installer now also refreshes
  LaunchServices' record of the bundle, which is the suspected cause; that this fixes it could not be shown.

- **The installer** (`tests/install_test.sh`, 49 checks, and `tests/release_test.sh`, 8 checks on the real release
  archive): install, install again, undo and uninstall leave Steam's folder byte-identical to before; the whole install
  runs with only tools every Mac has (a run with `unzip` taken away fails, so the check can fail); it works when piped
  into `bash` like `curl | bash`; a damaged or missing download is refused and nothing is installed; macOS versions too old
  are refused with a message. The real Korean translation `.rar` installed through `--pack` gave a `data.win` identical to
  the one set up by hand earlier. The same line from the README, run against the published v1.0.0 release, installed the app on the machine that built
it, and Play in Steam started the game afterwards. Not shown: a Mac that really lacks the Xcode command line tools, and
a person choosing a file in the `--pack` window (the window opens; nobody has clicked through it).

The report from your own run has the exact numbers for your machine.

## Reading the baseline

`python3 verify/verify.py --update-baseline` records the screenshot hashes of the scenarios for the current Mac, macOS
version and runner build. Later runs compare against it, so a runner update that changes how anything looks is caught.

Hashes are not expected to match between different Macs: the graphics driver can change pixels slightly. That's why the
baseline is stored per machine and not in the repository. Determinism is checked on one machine, across two runs.

## What is not covered

- **Comparison with the original runner.** Nothing here shows that the original would have drawn or behaved the same;
  it shows the game runs, consistently, without errors and with the expected flow. This is the main gap.
- **Sound as heard.** Decoding is proven. Whether it comes out of the speakers right isn't.
- **The drink-mixing minigame.** It is dragged with the mouse and gated on game state the scripted session doesn't set
  up. The rooms load and run, but nobody has mixed a drink automatically.
- **Rooms entered by warping** run for 150 frames each. That shows they load and don't error, not that they play.
- **Anything that waits for sound to finish.** The sequences at the end of the game move on only when the current song
  ends. Sound runs on the real clock while scenarios run faster than real time, so those sequences aren't reproducible.
  The room traversal stops right before them for that reason.
- **The Steam hook after Steam changes the game.** "Verify integrity of game files" or an update puts Steam's own
  `Mac_Runner` back. `install.sh --doctor` shows the state of the Play button and running the installer again connects it. Which
  Steam actions do that was not tested.
- **Dynamic calls.** The game runs a few scripts chosen at run time (dialogue commands). The call graph in the static
  check can't follow those; the report says how many such sites exist.
- **Other Macs.** Intel and older macOS versions are built in CI (both slices compile and have the right minimum
  version), but the Intel slice has not been run.

## Closing the main gap

Comparison needs a reference. The options, cheapest first:

| Option | What it takes | What it gives | Catch |
|---|---|---|---|
| Community checklist | Publish the repo; people tick [QA_CHECKLIST.md](QA_CHECKLIST.md) on their Macs | Real play on real hardware, including audio, Intel and older macOS | Reports, not measurements |
| Windows build as reference | A Windows VM (or Wine) with the Windows build from Steam; drive it with the same scenario using a key/mouse injector; compare screenshots at fixed checkpoints | A real oracle for menus, dialogue and layout | The original can't replay our recordings, so timing has to be matched by hand and random events differ |
| An old Mac with the original 32-bit runner | A Mac still on macOS 10.14 or earlier | The same oracle, from the Mac build itself | Needs the hardware, and the same injection problem |

Recording your own session (`--record-inputs`) and sending it adds a regression test for what you did, which is what
the checklist can't give.
