# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Spectating: when the player you watch skips ahead, your view now jumps straight there and keeps up as usual (it fell up to 2 seconds behind and caught up slowly). In a lobby, the host's skip no longer hides the notes on a spectator's screen
- Skipping ahead in solo play moves the music right away (it played on from before the skip for a moment, and for good with Disable Desync on)
- Staff can now set your level and prestige; your game takes it the next time it is online and tells you ("set by staff")
- Ranked maps: if your copy of a ranked map has different notes than the ranked version (so passes on it don't count), the map's screen now has a "Get the ranked version" button that downloads the right copy and swaps it in. Your old copy is kept in the map_backups folder
- Maps no longer lose part of their notes after you restart the game (maps with a tempo marker, like Camellia - Flamewall, started minutes in with "SP Not Valid"). Nothing to re-download: your map files were never changed
- Map Editor: Load map works again when it asks for the song after the map file (picking the song did nothing and it kept saying "Now pick the song"). The same goes for Paste map and every other place that asks for two files in a row
- Settings no longer reset at a restart when one setting in your file has an unexpected value: the game used to stop reading the file at that setting, leave everything after it at default and then save it that way. (The reset that came from signing in during startup was fixed in nov13-2026-a.)
- PC: the game no longer freezes for a moment about two seconds into a song (the anti-cheat scan ran right then). On maps that start early the first note popped in late and close, or didn't show at all. The scan now runs while you're in the menu
- Your own profile picture shows again in a map's History list and the Sound Space menu when it is kept on the Chromia server (its address was incomplete)
- Windows: starting a second copy of the game (e.g. the test build next to the stable one) no longer shows a crash report for the copy that is still running
- Settings > Transfer > Settings backups: copies of your settings are kept in a settings_backups folder so they can't be lost. Back Up Settings (on) makes the copies; Only When Saving a New Profile (on) makes one each time you create a profile, and with it off a copy is made every time your settings change. Back up now, Restore a backup (adds it as a profile) and Open backups folder are there too
- New cards and frames: Ranker, Contributor, Tester and Moderator each get their own card and frame (trophy, heart, flask and shield), and Prestige 1, 10, 100, 1,000 and 10,000 each unlock a card and a frame (bronze, silver, gold, diamond and the rainbow)
- The Cards and Frames menus only show the ones you have unlocked (admins see all of them)
- Notes are drawn the way they were before the stacked / dense notes change: every note of a stack is drawn again (see-through notes on one square build up as they used to), and far notes of long stacks are no longer thinned out
- The Spectate window is much lighter, most of all in VR: players' picture frames are drawn once for everyone showing the same frame instead of once per player 30 times a second (with 30 framed players the window took 3 times as long to draw; now it is close to having no frames at all). The Online list and the Frames menu gain the same
- Map list > Filters > Show: new "unranked" box shows only the maps that aren't ranked (ticking it unticks "ranked", and the other way round)
- Settings: a number box no longer stretches right across the page after its hint has shown (it happened when the mouse rested on a setting with a long hint, like Approach Rate, and stayed until the menu was reloaded)
- Map screen: the "Get the ranked version" button no longer runs into the Start button (there is room between them now)
- Removed the experimental Modern UI (it was only shown to staff)
- Meta Quest: opening the game no longer leaves you looking at nothing for a long time. VR now starts first, and a panel in front of you says "Loading" (with what is being loaded) or "Updating" (with how far the download is) until the menu opens. The game also no longer builds a flat menu it then threw away before the VR one, so it opens sooner
- VR: the loading panel of Reload Content, a profile switch and a skin change is the same new one (bigger, with moving dots, and it stays in front of you)
- Rhythia Nightly (and other older clients) get your bests and attempts back: the ones Chromia saved in the shared SoundSpacePlus folder were in a newer format they saw as broken. The first start of this version writes every map's bests there again in the older format, with the ones you made in Chromia since added (the better of the two for each speed and mods). The old files are kept in Chromia's folder
- Settings > Notes: Half Ghost strength goes in 1% steps instead of 5%
- Replays: the 360 mod shows when you watch one (the notes stayed still), and on the website's Game view at the speed it was played with; video links you make send the 360 speed too
