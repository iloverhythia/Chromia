# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Fixed the cursor trail crashing the game in VR and sometimes not showing: Smart Trail is now drawn as one object instead of a new one for every piece (smoother on PC too)
- Settings > Video & Audio: No Delay (Experimental, PC) removes mouse movement delay in maps: every mouse movement is used as soon as it comes in, and VSync, the FPS cap and the Windows compositor's extra frame are off while you play (yours come back after the map)
- Settings > Replays & Misc > Experimental: Legacy Mouse Movement moves the cursor with the mouse the way Chromia's very first update did (its original mouse code)
- New modifier: Reverse. The map plays backwards, and so does the song (the first time you play a song with it, it takes a few seconds to turn the song around). Plays with Reverse are never ranked
- The settings preview plays the map you have selected (its notes at your speed mod), and in time with the music when you play the map's music in the menu
- Star ratings follow your speed: a 10 star map at 0.74x shows 7.40 stars
- VR: type with both hands on the keyboard at once (each hand's trigger types the key it points at, straight away)
- Leaderboards by device: every leaderboard in the game (the global one and each map's) has a dropdown for All devices, PC, VR, Quest, Spin or Phone, and so does each map's page on the website
- Each map's leaderboard shows the SP of every pass again (it showed 0)
- Background Editor: right-click a layer > Move to Space puts the picture in the song's world, behind the grid (it moves with the camera), with a Distance slider for how far away it stands
