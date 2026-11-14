# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Spectating: when the player you watch skips ahead, your view now jumps straight there and keeps up as usual (it fell up to 2 seconds behind and caught up slowly). In a lobby, the host's skip no longer hides the notes on a spectator's screen
- Skipping ahead in solo play moves the music right away (it played on from before the skip for a moment, and for good with Disable Desync on)
- Staff can now set your level and prestige; your game takes it the next time it is online and tells you ("set by staff")
- Ranked maps: if your copy of a ranked map has different notes than the ranked version (so passes on it don't count), the map's screen now has a "Get the ranked version" button that downloads the right copy and swaps it in. Your old copy is kept in the map_backups folder
- Maps no longer lose part of their notes after you restart the game (maps with a tempo marker, like Camellia - Flamewall, started minutes in with "SP Not Valid"). Nothing to re-download: your map files were never changed
- Map Editor: Load map works again when it asks for the song after the map file (picking the song did nothing and it kept saying "Now pick the song"). The same goes for Paste map and every other place that asks for two files in a row
- Settings no longer reset at a restart when one setting in your file has an unexpected value: the game used to stop reading the file at that setting, leave everything after it at default and then save it that way. (The reset that came from signing in during startup was fixed in nov13-2026-a.)
