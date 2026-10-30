# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Phones: No Touch Delay now has a Prediction slider (how far ahead of your finger the cursor sits, 0-45 ms) and the cursor glides smoothly between touch readings instead of stepping, so play feels less laggy and less choppy, especially on 120 Hz screens
- Fixed: the retry key after leaving a map now starts it again (it only highlighted the Start button)
- Update boxes have a new Remind me in a day button: no update pop-ups for a day (Settings > Check for Updates still works)
- Settings > UI: Hide Spectators List (no list of who's watching in the top left while you play a map)
- Test builds say clearly that scores go to the test leaderboards, not the real ones (when the menu first opens and after each pass)
