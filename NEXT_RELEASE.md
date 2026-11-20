# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Android phones and tablets: less delay between your finger and the game, in songs and in the menus. The engine was handing touches to the game one frame late (after drawing instead of before); now they are used in the frame they arrive in
