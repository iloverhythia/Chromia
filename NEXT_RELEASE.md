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
- Staff: the in-game admin panel is gone (everything is in the website's admin panel)
- iPhone: 120 Hz no longer leaves you at a delayed 60. With the game's engine an iPhone asked for 120 frames a second drops to 60 and feels late, so the game now tries 120, then 80, for a few seconds in the menu and keeps the highest one the phone really holds. What it's running at is shown next to the 120 Hz setting, and it's remembered
- iPhone: installing the latest chromia-ios.ipa once lets the game also try two other ways of showing frames that may reach a real 120 (in-app updates can't add that part)
- Phones: ticking 120 Hz with a Max FPS under 120 set now really takes the limit off (the Max FPS box used to put it straight back, which left 120 Hz at 60 with extra delay). Setting a Max FPS under 120 turns 120 Hz off
- iPhone: a Max FPS at or above the screen's rate is taken off, because there it only showed every frame late
- When the game crashes, its crash report is sent to the developers by itself at the next start, so bugs can be found without you copying anything (what the game was doing, your version and device; never your account id). Settings > Crash Reports turns it off. Not in the browser version
