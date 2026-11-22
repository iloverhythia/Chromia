# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Map list: two new filters on the Filters page, "completed" (only maps you have passed, with any mods or speed) and "uncompleted" (only maps you haven't passed yet). The map you are on stays in the list, so passing a map with "uncompleted" on doesn't reset your filters
- Map leaderboard (in the game): clicking a score now plays that pass's replay in the game instead of opening the website. Right-click a score to open the player's profile
- Friends and blocking: right-click a name in any chat to add a friend or block them, and Online > Friends has your friends (who's online, Invite), friend requests and who you blocked. Blocked players' chat messages fold into "1 blocked message  Show" (click Show to see them), and their friend requests and lobby invites don't reach you. The website's profiles have the same buttons and lists
- Save video for any run, not just the last one: every attempt in a map's History tab has a camera button, and History has a "Newest first" switch so your recent plays are at the top. (Holding restart after a fail used to make Save video show the second-long restart instead of the run you wanted.) Leaderboard passes with a replay have the camera button too
- Offline Mode (Settings > Online): play on your own. You show as offline to everyone (not in Spectate, offline to friends and on your profile), nobody can watch, invite or collab with you, no chat shows (global, lobby, @mentions, friend request pop-ups) and you can't host, join or watch. Your scores aren't sent (no XP, SP or leaderboard places), but local RP and your History still count. Maps, updates and announcements still work. The Online page has a Go online button to turn it off
- Scrolling in a chat (the Spectate window's chat, the Online panel) or any window over the menu (Friends, Invite players, Filters...) no longer scrolls your map list behind it
- The Spectate window stays smooth with a lot of people online (it used to redo every player's card every second, on screen or not): much less lag on every device, VR and phones most of all
