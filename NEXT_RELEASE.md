# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Spectating: the eye button's Spectate window (who's online and the global chat) works while you watch someone, instead of the small corner chat
- Banned from chat: the chat boxes and Send buttons go grey ("You're banned from chat")
- Following someone you spectated works again after closing the Spectate window, and when they replay the same map
- VR: spectators see your hands (furry paws or your custom vr_hand.obj)
- VR: Settings > VR > Pointer > Hide the beam (pointing still works)
- Drag colorsets (.txt) and note meshes (.obj, with or without .mtl) onto the game to add them
- Dragging a settings profile (.json) onto the game adds it as a new profile instead of loading it over your settings
- Editor: the waveform on the track draws half as many lines, so the editor runs smoother with it on and zooming is less jumpy
- Emoji in chat: they show as pictures (Twemoji) in the Spectate window's global chat and in lobby chat
- Your attempts list (History) shows your profile picture instead of your first letter (your Chromia picture if you don't use Discord), with bigger, clearer rows: the top three get a ring in their colour and the rank sits on a badge under the picture
- Map editor: a SETTINGS button on the editor's start screen opens the editor settings without opening a map first, and long mapper names no longer push your map list under the buttons
- Settings: all the Sound Space settings moved to their own Sound Space section in the UI tab, with a new Sound Space HUD option: the side panels, time and health bar look like Sound Space's (pixel font, multiplier box, COMBO, misses and notes) while everything else stays yours. Spectators see it too
- Settings > Fonts (new tab): pick the font of the HUD while you play (Lato, Roboto, Ubuntu Mono, two pixel fonts, Noto Sans JP) or use your own .ttf / .otf font. The people spectating you see your font too (needs the updated server)
- Settings > Online > Share My Maps With Spectators: turn it off for unreleased maps. People can still watch you, but your map is only passed along for that watch: the server doesn't keep it and it isn't saved in their maps (it's deleted when they stop watching)
- The Map Browser is now the Content Browser, with tabs for Maps, Colorsets, Note Meshes, Settings Profiles and Cursors. Maps come from rhythia.com or from other Chromia players; everything else is shared by players. Press Add / Use / Download to get it straight into the game (great on a standalone VR headset), and upload your own files or share the colorset, mesh, cursor or settings you use now (size limits: maps 30 MB, meshes 6 MB, cursors 2 MB, profiles 512 KB, colorsets 64 KB; needs the updated server)
- Editor: the waveform is drawn as a picture once and reused, so playing the song in the editor no longer lags
- New colorset: Seaside
- Map editor: map together! COLLABORATE on the editor's start screen invites someone who's online (up to 5 people, with your Chromia accounts). The host's map and its song go to everyone, and every edit is live: notes, timing points, bookmarks and objects. You see where the others are in the song, their mouse over the grid, and the notes they placed in their colour. Turn invites off in the editor's Settings > Other (needs the updated server)
- Mapping together: leaving no longer leaves the other person's line and name on the screen, and when someone is in another part of the song an arrow at the edge of the track shows their name and where they are; their marker sits on the song bar at the bottom with their name
- Map editor: the waveform no longer lags at all. It's drawn by the graphics card from data worked out once when the song loads, so playing, scrolling and zooming don't stutter (they used to hitch for up to 40 ms), and changing the waveform's level of detail no longer freezes the editor
- VR: you can type in the global chat (the keyboard showed up behind the Spectate window), the menu screen looks smoother (less jagged, shimmering text), foveated rendering defaults to Low (Medium made the edges of your view pixelated; Settings > VR changes it), Reload Content shows its progress on a panel in front of you instead of leaving you in the dark, and the Spectate eye no longer covers the screen's resize handle
