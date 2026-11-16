# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- New Absolute Mode (Settings, under Absolute Mode): the cursor is put exactly where your finger or mouse is on every sample, with nothing smoothed. On a touch screen it leads by the Prediction amount at once and is back on your finger the moment you stop. Snappier and less even than Absolute Mode alone
- VR: the menu no longer crawls. When the headset didn't reach its refresh rate (120 Hz set, 60 to 72 frames a second made), the menu screen was only redrawn 15 to 18 times a second and stayed that way. It is now redrawn at least 36 times a second while you use it, whatever the headset manages
