# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Watching a replay: the replay bar has a Save video button, to make a video of the replay you're watching (it opens your browser, like Save video after a play)
- New mod, 360 Shuffle: like 360, but the spin keeps changing speed and direction. It isn't random: every map has its own pattern, the same every time you play it (and in its replays), so you can learn it. 360 speed sets how fast. It has its own best scores, apart from plain 360
- Blocking without the website: Online > Friends > Blocked has a "Block someone by player number" box, a friend request has a Block button, and the ... menu on a player in Spectate has Block / Unblock (and Add friend). Right-clicking a name in chat still works too
- Settings: right-click a category in the list on the left to hide it ("Hidden" at the bottom of the list shows them again; search still finds what's in them). And a new setting, Replays & Misc > Experimental > Collapsible Groups: click a group's title (Modifiers, Camera...) to fold it shut; it stays that way
- New mod, Blox Saber: no pause cooldown, so you can pause again right after unpausing, and from the very start of a map; unpausing takes a quarter second instead of 0.75. Scores with it aren't submitted (no XP, SP, RP or leaderboard), and it has its own best scores
- Picking a map with an animated (GIF) cover no longer holds the menu up for seconds: only the cover's first picture is read for the still one, not the whole animation.
- When the game freezes (the window stops answering), the next crash report now says what it was stuck on: the step it was in the middle of, the background jobs running, and whether the sound system or the graphics driver had stopped answering. Before, a freeze left nothing to go on.
- The game can no longer wait forever for a map's notes when another job that was reading them stopped half-way.
- The Spectate eye button can be dragged anywhere on the screen (mouse, finger or VR pointer) and stays where you leave it. A plain click still opens Spectate; right-click the eye to put it back in its corner.
- Direct messages: friends can message each other in the game. The chat (the eye button) now has three tabs: Global, DMs and Announcements. DMs lists your friends and conversations with unread counts; messages sent while someone is offline are waiting for them, and a new one shows by the eye button.
- Add a friend without leaving the chat: type a player's name or #number in the DMs tab, and accept or decline friend requests right there. The Friends window (Online > Friends) finds players by name too and has a Message button.
- Announcements tab: the team's latest announcements stay there to read, also the ones sent while you were away or in a map.
