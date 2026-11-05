# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Fixed the cursor trail crashing the game in VR and sometimes not showing: Smart Trail is now drawn as one object instead of a new one for every piece (smoother on PC too)
- Settings > Video & Audio: No Delay (Experimental, PC) removes mouse movement delay in maps: every mouse movement is used as soon as it comes in, and VSync, the FPS cap and the Windows compositor's extra frame are off while you play (yours come back after the map)
- Settings > Replays & Misc > Experimental: Legacy Mouse Movement moves the cursor with the mouse the way Chromia's very first update did (its original mouse code)
- Settings > Replays & Misc > Experimental: Modern UI, a new main screen: your maps as a grid of covers (ranked, stars, mapper, difficulty and length on each), the picked map on the left with its cover, leaderboard, your best, stats, a preview bar, Play / Practice with the most RP you can get, Autoplay and your mods, and a top bar with your profile, the pages and the search
