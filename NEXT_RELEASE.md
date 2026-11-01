# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.

- Fixed a crash when you start watching someone from the Spectate window (since nov1-2026-a)
- Fixed a possible freeze in the menu on ranked maps (since nov1-2026-a), and the Spectate window shows pictures uploaded to Chromia again
- Map screen: History uses the whole row, so your attempts aren't squished (the Modifiers box comes back when you switch to Best)
- Downloading maps: when a map can't be saved, read or converted, you're told why (it failed without a word and the map stayed unconverted)
- VR: maps no longer load to a black screen when the game wants to warn you about something (high cursor trail detail, broken audio, unusual approach rate or hit window): the warning was a flat-screen question the headset didn't show, so the game waited forever
- Profile: the old name box is gone (your name is your Discord / website profile name, and lobbies use it too)
- Fixed a crash right after a map finished downloading (most often in VR): the map was set up while the background star rating could be reading it
