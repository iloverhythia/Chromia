# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Spectators list in the top left: the player and everyone watching see who is spectating (hidden when nobody is)
- Watching someone from the Spectate tab no longer shows the one-player leaderboard on the left
- VR: hitboxes feel like on PC. Your hand is closer to the grid than your eyes, so notes took a bigger turn of the controller to cross than they looked and felt a bit bigger. Turning the controller now moves the cursor as far as that turn looks from your eyes (the hitbox itself is the same size). Settings > VR > Pointer > Hitboxes feel like on PC (on by default)
- Spectate tab: the # on each player is their leaderboard rank (SP), not their player number
- Map list: a small TOP button above UP takes you straight back to the top of your map list
- NEW: Colorset HUD (Settings > UI, under Rainbow HUD): the HUD's text, numbers and bars take the colour of the notes you hit
- Settings > Update channel is shown to anyone who has run a test build once (also in stable builds), so you can switch between stable and test without downloading again
