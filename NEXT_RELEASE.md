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
