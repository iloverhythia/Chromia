# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- New Absolute Mode (Settings, under Absolute Mode): the cursor is put exactly where your finger or mouse is on every sample, with nothing smoothed. On a touch screen it leads by the Prediction amount at once and is back on your finger the moment you stop. Snappier and less even than Absolute Mode alone
- VR: the menu no longer crawls. When the headset didn't reach its refresh rate (120 Hz set, 60 to 72 frames a second made), the menu screen was only redrawn 15 to 18 times a second and stayed that way. It is now redrawn at least 36 times a second while you use it, whatever the headset manages
- VR multiplayer: the scoreboard beside the left panel is turned towards you. It was angled away, so you saw it nearly edge-on and the scores were hard to read
- PC: fixed a small stutter once a second during maps. Every second the game checked which HUD panels have a moving background by asking the graphics thread for a shader's code, and the whole game waited for the answer. It is asked once now
- A slow frame during a map no longer makes the next frame slow too (the note about it for the log waited for the graphics thread and the disk)
- VR and phones: the cursor trail no longer gives up when the frame rate drops. Each frame's new trail was only drawn a frame later; at a low frame rate with a short Trail Time it had already faded by then, so the trail came apart from the cursor or vanished
- Cards and Frames: the window no longer grows down past the bottom of the screen after you pick one, and with many cards or frames the list scrolls instead of running off the screen
- The lobby invite notice during a song is its normal small size (it came out as tall as the screen)
- Videos: the Chromia mark is in the bottom left corner instead of the middle of the left edge
- PC: new "Limit FPS in Menus" (Settings > Video & Audio > Graphics, on from the start). In the menus the game draws as often as your screen shows (144 times a second at most) and 30 times a second while its window isn't in front, instead of as often as the graphics card can: a few percent of a fast card instead of nearly all of it. Maps aren't touched: your Max FPS, or no limit
- Max FPS typed while Streaming Mode holds the frame limit is taken now (it was ignored until Streaming Mode was turned off)
- Settings > Crash Reports: "Copy this session's log", for a problem that is not a crash (a map where the cursor or the HUD does not work on your computer). The log now also says what a song is started with (screen, mouse, controllers, HUD) and whether the mouse moved the cursor in its first seconds
