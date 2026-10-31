# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Fixed: spectating looped (the map reloaded over and over) and spectate settings didn't load in oct30-2026-c
- Spectate window: players are in leaderboard order
- Profile > Leaderboard: Weighted (SP) comes first and is shown by default
- The Wave Menu is now the default menu, in its own colours (turn it off or use your colorset in Settings like before)
- New announcement banner: a dark card at the top in the Spectate window's style that slides down, with who sent it
- Spectating: a bar at the bottom while you're joining someone, their song is loading, or you're following them to their next song, with a Stop button
