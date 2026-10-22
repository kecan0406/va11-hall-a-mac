# Manual checklist

The automatic checks can't hear, can't judge how something looks, and don't play the drink-mixing minigame. These are
the things a person has to try. Tick them off on your Mac and report what you find, with your macOS version, Mac model
and whether the display is Retina.

Play from a fresh start if you can (move `~/Library/Application Support/VA-11 Hall-A/saves/` out of the way). If you want
to share a session as a test, start it with `--record-inputs my_session.json` (see [SCENARIOS.md](SCENARIOS.md)).

## Sound (the automatic check only proves every sound decodes)

- [ ] Title screen has music
- [ ] Music plays in the bar, and changes with the track chosen in the Jukebox
- [ ] Sound effects play (clicking, pouring, serving)
- [ ] Volume sliders in Settings change the volume of both music and effects
- [ ] The tracks that used to be silent play now
- [ ] No crackling, stutter or music cutting off after a few minutes

## Mouse (patch 0002)

- [ ] The hand cursor sits exactly under the real cursor, at the top, middle and bottom of the window
- [ ] Same after resizing the window and in fullscreen
- [ ] Same on a non-Retina external display, and when moving the window between displays

## Drink mixing (not covered automatically)

- [ ] Dragging an ingredient from its can into the shaker adds it; the counter fills
- [ ] Ice and Aged toggles work; Reset clears the shaker
- [ ] Mixing and serving a drink advances the dialogue and pays out
- [ ] A wrong drink gets the matching reaction
- [ ] The recipe book opens and browses (By Name, By Flavor, By Type, Bottled Drinks)

## Game flow

- [ ] A whole in-game day, from the room it starts in to the end-of-day results
- [ ] Save, quit, start again, Load: the same state comes back
- [ ] Settings are remembered after a restart (language, volume, fullscreen)
- [ ] The shop works; the Jukebox plays the tracks you bought
- [ ] The shooting minigame starts and is playable with mouse and keyboard
- [ ] A game over leads back to where it should

## Fullscreen and windows (patch 0004)

- [ ] Alt+Enter enters and leaves fullscreen; so do the options menu and Cmd+F
- [ ] After leaving fullscreen the window is back where it was
- [ ] The game stays letterboxed (no stretching) at any window size

## Languages

- [ ] English, Japanese and Chinese all show their text, with no missing characters
- [ ] The language chosen on the first screen is kept

## Installing

- [ ] On a Mac without the Xcode command line tools, the one-line install in the README finishes and says "All set"
- [ ] The words on screen are clear enough that you knew what to do next, with no step you had to look up
- [ ] Running the same line a second time works and changes nothing you can see
- [ ] `--pack` opens a window to choose the file, and a downloaded `.zip` or `.rar` translation works
- [ ] `--uninstall` leaves the Steam game exactly as it was before (Play fails again as it did before)

## Steam's Play button

- [ ] Play in Steam starts the game, and the first Play right after hooking works
- [ ] Steam shows the game as running, and goes back to Play when you quit
- [ ] The game is in front and takes keyboard and mouse input straight away
- [ ] The Steam shortcut in `~/Applications` (if you made one) starts the game too
- [ ] An achievement you earn shows up on the game's page in Steam (`--doctor` says `Achievements: on`)
- [ ] After "Verify integrity of game files", `--doctor` says the Play button isn't connected and running the install line again brings it back
- [ ] `--uninstall` makes Play fail again as it did before and removes the two apps; running the install line again brings everything back

## Overrides and translations (docs/MODS.md)

- [ ] With a translation pack in `overrides/`, text in menus, dialogue and the bar interface is in the pack's language,
      with no missing or garbled characters
- [ ] Removing the pack from `overrides/` brings the original text back on the next launch
- [ ] Settings and saves are kept when switching between the original and a pack

## Other

- [ ] A game controller works, if you have one
- [ ] Quit from the game's Exit button ends the process (no stuck dock icon)
- [ ] Known gaps still behave as documented: F12 saves nothing
