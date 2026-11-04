# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- No more little stutter when someone starts spectating you in the middle of a map.
- In a map, the custom speed icon shows its speed (for example 137%).
- Settings has a small preview window ("Watching Auto play") that plays a short map exactly the way your songs look: your note mesh, colorset, note size, opacity, fade, half ghost and spin, approach rate and spawn distance, border, cursor, FOV, parallax, Spin and hit effect. Drag it by its top bar, resize it from its corner, close it with the x, or turn it off in Settings > UI > Settings Preview.
- Settings > Video & Audio: Exclusive Fullscreen is called Fullscreen again. It is the same fullscreen as always (the lowest input delay); Borderless Windowed is still there too.
- Spectating: you always see the map with the other player's settings when you pick theirs (sometimes their approach rate, spawn distance, note size and other number settings were swapped back to yours), also after they lose their connection for a moment.
- Lobbies: you can leave in the middle of a match. After giving up (or failing), hold the give up key again or press Leave lobby on the watching banner (in VR the panel shows which button): you go back to the menu and the round goes on for the others
- VR: no more lag at high speeds (200% and up) on dense maps. The game waited on the graphics card for every note on screen every frame, and made a new hit effect for every hit; it does neither now. PC gets smoother too.
- Spectating someone who plays with Spin shows it their way: the camera turns with their cursor like in their game (your own Spin setting stays as it is), the spectate banner says SPIN, and their card in the Spectate window says Spin.
- A controller left plugged in no longer grabs the cursor at the start of a song (it could stick in the middle and not move) when Disable Controller is ticked, and a resting stick no longer takes over otherwise.
- VR: the Map Folders window opens on the menu screen (it opened somewhere you couldn't see).
- Profile: a Reset RP button puts your offline RP back to 0 (it asks first; your XP, SP and level stay).
- VR: type with both hands. While the keyboard is up, your other hand's beam shows too and its trigger presses the key it points at.
- VR: grip calibration is easier (Settings > VR > Controller grip > Calibrate). The song grid shows in front of you and notes light up one at a time: move your hand to each the way you would in a song and pull the trigger, no careful aiming. Then a dot follows your hand on the grid with the new grip so you can check it (trigger keeps it, B / Y starts over).
