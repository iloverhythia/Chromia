# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Spectate moved from the sidebar to a round eye button in the bottom-right corner of the menu. It opens a big Spectate window: everyone online in a grid with their picture, what they're doing and their leaderboard place, a search box, a heart filter for your favourite players (heart someone on their card), and the global chat underneath. Click someone who's playing to watch them
- Map editor: no more lag from the waveform. The game froze for a moment when the waveform appeared, ran slowly while the song was being analysed, and at some zoom levels kept rebuilding the whole waveform while playing (very low FPS). Now it's built a little at a time, only where you look, and the song is analysed in the background without slowing the editor down
- Spectate: a smaller, cleaner eye button (drawn sharp at any size), smaller square player cards that show each player's device (PC, PC VR, Quest, Phone, Browser) and role, the search box at the top, the global chat in a column on the right, and the window slides in when you open it
- Map editor: the Settings window has a new look: a tab list on the left, settings grouped in sections with a short note on each, on/off switches, sliders that show their value, keybinds in two columns, and it uses most of the screen so everything is easy to read
- Settings scrolls smoothly with the mouse wheel (it glides instead of jumping)
- Spectating: you see the player's own custom border and note mesh with their settings (sent through the server like cursor pictures), and when they pause it shows Paused and waits, then picks up smoothly instead of stuttering (needs the updated server)
