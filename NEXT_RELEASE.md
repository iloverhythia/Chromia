# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Vaporwave (Roblox) background: fixed the lower half of the screen turning solid white (cutting the grid and HUD in half) whenever the camera rose a little, as it does in Spin and with parallax, and the sky turning flat grey when it dipped. The background has two huge paper-thin sheets lying exactly at eye level that were only ever meant to be seen edge-on
- Fixed a way the game could close by itself when a song started right after you picked a map (within about half a second): picking a map started a background check of its song that read in a script at the same moment the song's loading did
- A quick second click on a map in the list starts it the same way the Play button does (it had its own way in). The same click arriving twice no longer counts as a second click
