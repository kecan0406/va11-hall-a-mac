# Scenarios

A scenario is a short text file that drives the game with scripted mouse and keyboard input. `verify/verify.py` compiles
each one into the input recording the runner replays (`--playback-inputs`), so the same scenario plays the same way on
any machine. Frames are the game's own step counter.

## Events

One event per line: `<frame> <action> <arguments>`.

| Line | Meaning |
|---|---|
| `60 move 640 336` | put the cursor at game position (640, 336); the game surface is 1280x720 with the origin top-left. The position stays until the next `move` |
| `65 click left` | press the button on frame 65 and release it 3 frames later (`left`, `right`, `middle`) |
| `100 key alt+enter` | press the keys on frame 100 and release them 3 frames later; combine with `+` |
| `1000 warp shooting_room` | jump to a room by name (a test aid for rooms the game only enters through its own logic) |

A frame can be a repeat, `<from>..<to>/<every>`: `1100..2000/40 click left` clicks every 40 frames.

Key names: `enter space esc tab backspace shift ctrl alt up down left right pageup pagedown f1`..`f12`, `a`..`z`, `0`..`9`.

Until the first `move`, the cursor sits at (0, 0). A replay never lets the real mouse leak in, which is what keeps runs
reproducible.

## Directives

Lines starting with `@` tell `verify.py` how to run and judge the scenario. They are not part of the input.

| Directive | Meaning |
|---|---|
| `@exit 8600` | stop the game at this frame (required) |
| `@shot 990 title_menu` | take a screenshot at frame 990 and call it `title_menu` |
| `@rooms a b c` | the rooms entered, in order, must be exactly this |
| `@rooms-visit a b c` | these rooms must all be entered, in any order |
| `@debug` | run with the runner's debug keys (PageUp moves to the next room) |
| `@roundtrip` | replay while re-recording and compare the recording with the input |
| `@speed 8`, `@seed 1` | speed multiplier and random seed (defaults 8 and 1) |

## The scenarios that ship

- `golden_path`: a new game with the mouse only, from the language screen to the first shift: title menu, the notice
  after "New Game", the bar prologue, the "Chapter 1" card, Jill's room, and back to the bar. Text boxes are advanced by
  clicking inside them, which is why the cursor moves between the notice and the text box.
- `rooms_traversal`: PageUp walks the rooms in the game's room order, 90 frames in each.
- `rooms_warp`: after the intros, jumps into the rooms the traversal can't reach and lets each run for 150 frames.
- `mouse_roundtrip`: one click, replayed while recording.

## Recording your own

```sh
"$HOME/Applications/VA-11 Hall-A (native).app/Contents/MacOS/VA-11 Hall-A" --record-inputs my_session.json
```

The recording holds keyboard and mouse input per frame, with the mouse in game pixels. Replay it with
`--playback-inputs my_session.json` on a fresh save folder.
