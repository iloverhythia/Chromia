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
