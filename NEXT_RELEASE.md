# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Spectating: when the player you watch skips ahead, your view now jumps straight there and keeps up as usual (it fell up to 2 seconds behind and caught up slowly). In a lobby, the host's skip no longer hides the notes on a spectator's screen
- Skipping ahead in solo play moves the music right away (it played on from before the skip for a moment, and for good with Disable Desync on)
