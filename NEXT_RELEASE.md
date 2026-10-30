# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Tester accounts that switch to the stable version stay on it (the game no longer updates them back to a test build on start)
- The game can no longer get stuck updating back and forth between two versions: an automatic update that would undo the one just made is stopped (Settings > Update channel still switches any time)
