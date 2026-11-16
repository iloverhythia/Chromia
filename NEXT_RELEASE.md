# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- The game no longer sends usage data to Google Analytics
- The ban screen is gone: bans are handled by the server
- Meta Quest: moving from the sideloaded version to the store version. In the sideloaded version, Settings > Transfer > "Move to the store version" > "Send everything" sends your whole game through the game's server (your account, settings, profiles, scores, level, colorsets, meshes, skins, hands, and your maps and replays unless you untick them) and shows a code. The store version asks about it the first time it opens, and has "Bring everything over from the sideloaded version" at the top of Settings > Transfer: type the code there, then close the game and open it again. Nothing is removed from the sideloaded version; the code works once, for a day
- Settings: with New Settings UI off, a new Side Tabs switch (under it) puts the settings tabs in a list down the left side
- VR: heavy menu pages (the Content Browser's map cards most of all) no longer drag the headset's frame rate down. The menu screen is redrawn less often when frames start coming late, and more often again once they are on time; before, a page heavy enough to pull the frame rate under 80 was redrawn every single frame, which kept it laggy. Your view, hands and pointer stay at the headset's full rate
- VR: the Content Browser builds its map cards two a frame and loads two covers at a time, so opening a page of maps doesn't hitch
- Note meshes can be .glb files too (Settings > Meshes > Import, Import Content, or drop the file on the game)
- Videos: the Chromia mark is at the middle of the left edge instead of the bottom right corner
