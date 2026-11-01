# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- VR / phones: .rhm maps from rhythia.com (Content Browser) convert properly: they were converted without their music (and then wouldn't play) because the audio was looked for in the wrong folder
- VR: pressing Start after Random starts the map (the Random button could stay held, so Start picked another map instead)
- Spectating: you hear the hit and miss sounds of the player you watch (there were none)
- VR: while you watch someone, a panel above the right side says who it is and how to stop (hold your give up button); the Following / Stop bar shows on the menu screen in the headset
- Map editor is much faster: placing, deleting and moving notes on big maps no longer freezes for a moment (about 30 times quicker on a 20,000-note map, undo/redo too), and playing the song in the editor no longer slows every frame down
- Your Online status shows you playing again while you're in a map (it errored and wasn't sent)
- Map screen: a Leaderboard tab (next to Best and History) on ranked maps shows everyone's best pass, top first: their picture, SP, accuracy, misses and speed (click someone to open their profile)
