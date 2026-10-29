# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Scores now remember if they were played in VR or on a phone/tablet (the website shows VR / Mobile / Spin badges)
- Settings > Update channel: switch to test builds (new things first, on the test server) or back to stable
- Ranked passes are sent with their replay (needed for XP now, and anyone can watch them on the website). Replays are recorded even with Record Replays off; those are deleted again when you're back in the menu
- Spectators list in the top left: the player and everyone watching see who is spectating (hidden when nobody is)
- Watching someone from the Spectate tab no longer shows the one-player leaderboard on the left
- VR: hitboxes feel like on PC. Your hand is closer to the grid than your eyes, so notes took a bigger turn of the controller to cross than they looked and felt a bit bigger. Turning the controller now moves the cursor as far as that turn looks from your eyes (the hitbox itself is the same size). Settings > VR > Pointer > Hitboxes feel like on PC (on by default)
- Spectate tab: the # on each player is their leaderboard rank (SP), not their player number
- Map list: a small TOP button above UP takes you straight back to the top of your map list
- NEW: Colorset HUD (Settings > UI, under Rainbow HUD): the HUD's text, numbers and bars take the colour of the notes you hit
- Settings > Update channel is shown to anyone who has run a test build once (also in stable builds), so you can switch between stable and test without downloading again
- The retry key no longer jumps into the map search box in the menu
