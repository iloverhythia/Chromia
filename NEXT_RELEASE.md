# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Phones: No Touch Delay now has a Prediction slider (how far ahead of your finger the cursor sits, 0-45 ms) and the cursor glides smoothly between touch readings instead of stepping, so play feels less laggy and less choppy, especially on 120 Hz screens
- Fixed: the retry key after leaving a map now starts it again (it only highlighted the Start button)
- Update boxes have a new Remind me in a day button: no update pop-ups for a day (Settings > Check for Updates still works)
- Settings > UI: Hide Spectators List (no list of who's watching in the top left while you play a map)
- Test builds say clearly that scores go to the test leaderboards, not the real ones (when the menu first opens and after each pass)
- Fixed: spectating someone with a custom speed (or joining a lobby whose host has one) used your own custom speed instead of theirs, so the notes went out of sync
- Fixed: the Spectate tab showed the wrong difficulty on maps (one step too high: most showed Logic)
- Map editor: LOAD MAP now also opens Rewrite (.phxm), Novastra (.npk / .nch), SSQE (.qem / .qemz), Pulsus (.phz) and Vulnus (.zip) maps, with their lyrics, beats, glides, mines, fevers, bookmarks and effects (Vulnus maps with several difficulties become one map each)
- Map editor: EXPORT can now make Novastra (.npk) charts, with cover, profile icon, song offset and preview, and SSQE (.qemz) maps that keep everything in the map
- Map editor: Rewrite (.phxm) exports now include the part of the file other editors expect after the notes
- Map editor settings from SSQE+: Grid Squircle Corner Radius and Corner Detail, Waveform Level of Detail and Show Control Gradients (Graphics), Mono Audio (Audio), and SSQE+'s own note colour list (Colors: pick, add, remove and reorder colours; turn on Use These Note Colors to use it instead of your colour set)
- Map editor: EDIT LAST MAP on the editor's home opens the map you edited last, and a new keybind opens the editor folder (Ctrl+Shift+D)
- Fixed: the game could crash while closing after Score History or the Sound Space menu had shown Discord pictures (the next start then said Chromia crashed)
