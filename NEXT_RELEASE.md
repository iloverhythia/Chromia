# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Settings > World & Cursor > Co-op Partner Cursor: how see-through your co-op partner's cursor is on your screen (0% hides it; only on your screen)
- Meta Quest: the game is sharp again in VR. Foveated rendering on Auto had been turned up to High, which made the view very pixelated: Auto is back to Low at the normal render resolution (pick High yourself, or press "Best frame rate", if you want the extra frame rate)
- Co-op: you fail together: when your shared health runs out, the round ends for both of you instead of one watching the other. Left / right now keeps each cursor on its half of the grid (the middle column is for both, and every note is fully shown), and in Take turns you only see your own notes (every other one): your partner's aren't shown
- Co-op is harder: a hit gives back half as much health as playing alone (a miss still costs the full amount). Since a note only costs health when you both miss it, the shared health bar hardly ever ran out
