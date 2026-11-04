# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- No more little stutter when someone starts spectating you in the middle of a map.
- In a map, the custom speed icon shows its speed (for example 137%).
- Settings has a small preview window ("Watching Auto play") that plays a short map with your settings, so you can see what a change does. Drag it by its top bar, resize it from its corner, close it with the x, or turn it off in Settings > UI > Settings Preview.
- Settings > Video & Audio: a normal Fullscreen option next to Exclusive Fullscreen and Borderless Windowed. It fills the screen the game is on and stays an ordinary window, so Alt-Tab is quick and overlays work.
- Spectating: you always see the map with the other player's settings when you pick theirs (sometimes their approach rate, spawn distance, note size and other number settings were swapped back to yours), also after they lose their connection for a moment.
- Lobbies: you can leave in the middle of a match. After giving up (or failing), hold the give up key again or press Leave lobby on the watching banner (in VR the panel shows which button): you go back to the menu and the round goes on for the others
- VR: no more lag at high speeds (200% and up) on dense maps. The game waited on the graphics card for every note on screen every frame, and made a new hit effect for every hit; it does neither now. PC gets smoother too.
