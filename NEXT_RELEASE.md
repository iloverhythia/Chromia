# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- VR replays watched from the player's eyes use the VR view settings (no camera unlock or parallax, as when spectating someone in VR) and show the player's own hands: yours in your own replays, theirs on Save video links
- VR: breck's snow leopard paw now shows up in Settings > VR > Hands. The game only found out which player you are after you had opened Spectate or Online, so the hand was missing (and, if already picked, shown as the Furry paws). It now asks once right after connecting.
- Save video's Game view can make 120 fps videos (owners only for now)
- Map list: Filters > Show > embossed shows only maps by Embossed (sorted as usual)
- VR and phones: the cursor trail is lighter. Its shader is no longer rebuilt at the start of every song (a stall when the first piece appeared), it is drawn in one pass instead of two, a very high Trail Detail no longer makes more pieces than you can tell apart, and less data goes to the graphics card each frame. It looks the same at normal settings.
- Each song now leaves a "song perf" line in the game's log (frame rate, slow frames, the worst frame, VR refresh rate, trail settings). With Settings > Replays & Misc > Experimental > Always show crash logs on, the next start shows the log with a Copy report button, so a lag report comes with numbers.
- Replays: Cursor Face Velocity works (the cursor turns the way it moves, as when you played)
- Spectating and Save video links play the player's own hit and miss sounds (the song loading put yours back)
- Replays (and Save video): at the very end the cursor stays where it was, instead of gliding in a straight line back to the middle
- Visual maps: notes no longer pop in partway down the lane. The game drew at most 512 upcoming notes at once, so on dense maps the rest appeared closer than the others; it now draws as many as your computer keeps up with (all of them in Save video renders)
- No "What's New" popup after an update (the notes are still in the Update Log)
- Spectating remade: smooth playback that holds more in hand when the connection is uneven (it eases the speed a few percent instead of freezing and jumping), the music follows without stutters, and every frame's cursor position is sent, so the cursor moves exactly as theirs did
- Update channel: test builds are for testers set on the website (a Tester role badge). Only they see the Update channel switch; everyone else gets the stable build, even after downloading a test build
- Spectating: Cursor Face Velocity and Cursor Spin work on the cursor you watch
- Upgrade tree: saved as upgrade_tree.json (was furry_tree.json, renamed by itself), laid out to be read: totals first, one line per upgrade
- Maps with huge stacks of notes (a thousand on one square, or far too many at once) look right: the stack reaches all the way back instead of being cut short with the cut moving back and forth. When there are more notes on their way than a frame can place, the nearest are all drawn and the far ones are thinned evenly rather than dropped; notes on the very same spot and moment are drawn once. Hits, misses and score are untouched.
- Big maps are lighter to draw: the list of notes sent to the graphics card each frame is as long as what is on screen, not as long as the whole map.
- Multiplayer: the Spectators list sits under the lobby leaderboard instead of on top of it
- Spectating: the music keeps its normal pitch (it sounded sharp while playback evened out)
- The speed modifier icons while playing are round again (they were stretched into ovals)
- VR: the Save video button shows on the results after a play (the link opens in the computer's browser)
- VR: replays remember which hands you had (furry paws, custom vr_hand.obj, ...), so watching them shows your hands instead of the default ones (needs the updated server)
- Seasonal themes: Christmas! From 1 to 26 December the menu waves turn red, green and gold, snow falls over the menu and a string of lights twinkles along the top (Settings > Replays & Misc > Seasonal Themes turns it off)
- Phones (iPhone, Quest): switching between the test and stable builds no longer loops (the app threw the test build away at the next start and downloaded it again)
- Settings no longer reset when you switch between test and stable builds (an older version only saved the settings it knew; the others now come back)
- Frame Smoothing now also keeps the game at a frame rate your device holds. When a song keeps dropping frames at a high refresh rate (a headset's 120 or 90 Hz, an iPhone's 120 Hz), the next songs run one rate lower (120 > 90 > 80 > 72 Hz on a headset, 120 > 60 Hz on an iPhone): a steady lower rate looks far smoother than a higher one that stutters. After a few songs without late frames the higher rate is tried again. It never goes above what you picked in the settings; changing the refresh rate setting by hand, or turning Frame Smoothing off, puts your rate back.
- Frame Smoothing: the even note steps now go by the real refresh rate of the headset or screen, so they hold while frame times are a little uneven (before, the game worked the rate out from the frame times and gave up when they weren't steady, which is when it was needed).
- Settings > Replays & Misc > Experimental: under Frame Smoothing, a line says how the last song went on this device (frames a second, how many frames came late, and the rate it is held at, if any).
- Your FOV setting works again for everyone: with Hit FOV decay at 0 the game always played at 70
- VR: switching settings profiles (also skins and Reload Content) no longer leaves the headset black at times. The loading screen behind those asked Android for the storage permission again every time, which takes the game out of focus for a moment on a Quest; it now asks once when the game starts. That screen also always brings back the menu in the headset, never the flat one on the window.
- VR: if the menu or a song fails to load, the message shows in the headset and the game goes back to the menu by itself (it was only on the flat window: black in the headset until a restart)
- If the menu fades to black to go somewhere and nothing follows, it comes back after a few seconds instead of staying black
- Faster on every device: the HUD panels (score, timer, combo, energy...) are each a separate picture the game used to draw again on every frame, changed or not. They are now drawn again only when something on them changes (in time for the same frame), so most frames skip most of them. It looks the same; the saving is biggest at high frame rates and on phones and headsets, where each extra picture costs the most.
- The combo ring, the "true combo" number and the rainbow SS grade no longer force their panel to be redrawn on every frame for changes too small to see
- Streaming Mode (Settings > Replays & Misc > Experimental, computers): for sharing your screen on Discord or recording with OBS. The game draws at three quarters of the frame rate your computer manages and leaves the rest of the graphics card free, so the stream and the game stop stuttering each other. It works the limit out by itself, never goes above your own Max FPS, and your Max FPS comes back when you turn it off. Only a frame limit: nothing about the game changes. (Does nothing with VSync on.)
- VR: a refresh rate above 144 Hz can be picked if a headset offers one (the list is the headset's own; Quest headsets go up to 120 Hz)
- Settings no longer reset to default at a restart. When the server's answer at sign-in (staff or not) came in before the game had read your settings, the game saved its defaults over your settings file; a start after switching between stable and test builds takes longer, so it happened there most. Nothing is saved any more until your settings have been read.
- The settings file can no longer be left empty when the game is closed or restarted in the middle of saving (it is written beside the old one and swapped in when complete), and a copy of your settings from the last run is kept next to it (settings.json.bak, and one per profile): if the file is ever empty or damaged, that copy is used instead of starting over.
- Levels: 10,000 prestiges instead of 10. If you were sitting at prestige 10, level 100, you can prestige again.
- Every prestige has its own badge next to your level in the Profile tab. The last digit of your prestige sets its colour, the tens add dots inside, the hundreds change its shape (hexagon, diamond, pentagon, stars, shield, circle...) and the thousands add spikes round it. Prestige 10,000 is the Chromia note in all its colours.
- At prestige 10,000, the last one, your level no longer stops at 100: it keeps going for good.
- Levels cost more with each of the first ten prestiges, as before (20% each); from the tenth on the cost stays the same, so the later prestiges are never out of reach.
- Passes with No Fail or Visual Map Mode on are no longer sent to the server (they showed up on your website profile as unranked passes). Turning on No Regen, Extra Energy or Sudden Death now turns Visual Map Mode off along with No Fail
- Owners: the Profile page has a Make alt account button: a second account for testing (a separate player with no staff permissions, tied to your Discord). The same button then switches between it and your main account
