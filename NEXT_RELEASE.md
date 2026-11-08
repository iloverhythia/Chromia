# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Quick restart: the map comes back in right away instead of fading in from black (the wait before the first note is Settings > Gameplay > Lead-In Time)
- Speed keys in the map list: press Ctrl+S, then A / D (or the arrow keys) to go through the speeds, Esc when done
- Your bests and score history are now kept in Chromia's own folder, so opening Rhythia Nightly no longer deletes them (they're copied over the first time you start this version)
- Spectating maps with lots of notes no longer drops frames when you start watching or their game catches up
- Staff can right-click a name in chat to delete that message for everyone or ban the player from chat
- Menus open faster on every device: the menu opens about twice as fast after a song, the Map Editor and Update Log open almost instantly, and the Settings page no longer waits for its preview window
- VR: Settings > VR > Hands > Hand direction: tilt, turn or roll your hand model so it lines up with your beam (the left hand is mirrored)
