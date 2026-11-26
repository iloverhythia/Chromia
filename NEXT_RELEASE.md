# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Settings > World & Cursor > Co-op Partner Cursor: how see-through your co-op partner's cursor is on your screen (0% hides it; only on your screen)
- Meta Quest: the game is sharp again in VR. Foveated rendering on Auto had been turned up to High, which made the view very pixelated: Auto is back to Low at the normal render resolution (pick High yourself, or press "Best frame rate", if you want the extra frame rate)
- Co-op: you fail together: when your shared health runs out, the round ends for both of you instead of one watching the other. Left / right now keeps each cursor on its half of the grid (the middle column is for both, and every note is fully shown), and in Take turns you only see your own notes (every other one): your partner's aren't shown
- Co-op is harder: a hit gives back half as much health as playing alone (a miss still costs the full amount). Since a note only costs health when you both miss it, the shared health bar hardly ever ran out
- Co-op plays are never your best score and don't go in your History: after a co-op round the map screen showed the co-op play as your best ("New best!")
- Settings > Notes > Half Ghost Start: choose when Half Ghost starts fading a note out, in milliseconds before you hit it (240 ms as before; it's faded fully at a quarter of that). Spectators and replays see yours
- Co-op videos: Save video of a co-op play (Game view) shows both of you: each player's notes in their own color (yours pink, your partner's blue) and your partner's cursor with their name, and the notes they hit count as hit in the replay
- Map Editor: AUTO LYRICS (GRAPHICS > Lyrics, on Chromia maps) finds your song's timed lyrics online (from LRCLIB, a free lyrics library) by the map's song name and places every line at its time. Pick another match from the list if the first isn't right, use Offset if your song starts earlier or later than the original, and Ctrl+Z takes them away
- Leaderboard replays: watching a pass with the player's settings no longer closes the replay and sends you back to the menu right after it starts
