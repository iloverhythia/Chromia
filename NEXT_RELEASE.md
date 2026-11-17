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
