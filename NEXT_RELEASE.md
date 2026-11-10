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
- Settings > Transfer: Include maps sends all your maps too (with the code over Wi-Fi or in the file); maps the other device already has are skipped
- VR: putting on a skin no longer leaves a black screen until you restart the game
- Map browser (Content Browser > Maps) is much smoother, especially in VR: covers are loaded in the background at card size and the cards appear a few at a time
- Replays (in the game and the website's Game view) now play with the lead-in the player used, so the cursor no longer drifts off the notes when your Lead-In Time is different
- VR (Quest): Settings > VR > Graphics > Unlock refresh rate: always runs at the highest refresh rate your headset offers (like 120 Hz) and keeps it after the headset sleeps
- VR: menus stay smooth: the animated menu background is drawn at lower cost in the headset, and two things that made the menu stutter every few seconds are gone (also on PC and phones)
- The popup when you start a ranked map now shows the SP a full pass gives instead of XP
- VR: switching settings profiles (or putting on a skin) no longer leaves the headset black until you restart: a profile's window settings (fullscreen, maximise, max FPS mode) aren't applied while VR runs
- Website: passes on unranked maps now show in your profile's Recent list with their replay, marked Unranked (no SP or XP)
- Map list: a BOTTOM button under DOWN jumps to the last map, like TOP does for the first
- VR: a snow leopard paw hand, only for breck (player #3)
- Settings > Fonts: 40 more fonts for the song HUD, grouped by look (clean, tall and narrow, sci-fi, pixel and monospace, fun), e.g. Poppins, Montserrat, Bebas Neue, Orbitron, Silkscreen, VT323, Bungee and Comic Neue
- Background Editor > HUD panels: 21 more panel styles, e.g. Neon glow, Pill, Double border, Gradient, Sunset, Ocean, Aurora, Rainbow border, Hologram, Corner brackets, Stripes, Dots, CRT scanlines and Carbon fibre (some of them move)
- Content Browser: maps from Chromia players show their cover picture.
- Content Browser: new "GitHub" choice next to rhythia.com and Chromia players. Paste a link to any GitHub repository (or a folder, release or map file in one) and every .sspm and .rhm map there is listed to download, one by one or all at once.
- The Profile, Leaderboard and Stats tabs on the Profile page have a new look that matches the Online page: bigger tabs, stat cards, tidy numbered rows, and your own row lit up on the leaderboard.
- Spectate: each player's card shows their speed, how far into the map they are and the time they have left, with a progress bar
- Profile page: both panels (Your Profile, and Profile / Leaderboard / Stats) are much less see-through, as solid as the Online page, so they're easy to read over any background.
- Staff: the in-game admin tools now come from the permissions the owner gave your linked Discord account (no admin key any more)
- Maps no longer show RP unless you turn it on: Settings > Replays & Misc > Experimental > Show RP on Maps (off by default). You still earn RP from passes, and your RP total and top 10 RP plays are still in the Profile tab.
- Profile > Leaderboard shows what the website's leaderboard does: each player's country flag, profile picture, tag (Developer, Owner...) and Ranked Team, their level and ranked plays, and how far ahead they are of the next player. Rows are roomier, and clicking one opens that player's profile on the website.
- Maps show their RP by themselves while the Chromia servers can't be reached (after about 12 seconds without a connection), even with Show RP on Maps off, and hide it again once the servers are back.
- Profile, Leaderboard, Stats and Online pages polished: nothing is cut off in the middle of a letter any more (long names end in "…", and leaderboard rows move "Ranked Team" down a line when there's no room), panel corners are smooth, lists don't run under their scrollbar, and the leaderboard, top RP plays and stats tiles have more room.
- Online: hosting a lobby at the default window size no longer squeezes the map's name into one letter per line (the Pick map / Use selected buttons sit under the name now), and the lobby chat's emoji button is small so its hint text fits.
- Switching to another window during a map now gives the mouse back to Windows, and coming back takes it again: fixes the cursor going missing with remote desktop or other games in the background
- Results: Save video makes a video of your play (a whole map or the part you played) on the website, with your settings: notes, cursor, camera, HUD and background
- Spectating with their settings now shows their own HUD panel picture too
- VR (Quest): a fix for the game closing right after you die with restart on death turned on. The song is now stopped for a moment before it reloads (about a fifth of a second), instead of being swapped out in the same instant.
