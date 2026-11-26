# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Settings > World & Cursor > Co-op Partner Cursor: how see-through your co-op partner's cursor is on your screen (0% hides it; only on your screen)
- Co-op: after you fail and watch your partner, their blue cursor no longer stays frozen on the screen (your cursor shows their moves while you watch)
- Co-op: you both see every note and either of you can hit it (the Take turns and Left / right ways are gone), and you fail together: when your shared health runs out, the round ends for both of you instead of one watching the other
- Meta Quest: the game is sharp again in VR. Foveated rendering on Auto had been turned up to High, which made the view very pixelated: Auto is back to Low at the normal render resolution (pick High yourself, or press "Best frame rate", if you want the extra frame rate)
- Co-op: you both see every note, and you fail together: when your shared health runs out, the round ends for both of you instead of one watching the other. Left / right now keeps each cursor on its half of the grid (the middle column is for both, and every note is fully shown), and in Take turns your partner's notes are only a little faded
