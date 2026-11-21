# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Android phones and tablets: less delay between your finger and the game, in songs and in the menus. The engine was handing touches to the game one frame late (after drawing instead of before); now they are used in the frame they arrive in
- VR (Meta Quest): the on-screen keyboard is much lighter to draw (one picture instead of fifty separate buttons), so the frame rate no longer sags while it is out. In VR the map search now updates once you stop typing instead of after every key
- VR (Meta Quest): a Chromia splash shows in the headset the moment the game is opened, the Loading panel is up and moving before the loading starts, and it keeps moving while the menu loads (the picture used to freeze for most of the loading)
- Phones: loading screens keep moving while a song or the menu loads instead of freezing until it is done
- Fixed small stutters in the middle of songs, most noticeable in VR: hit and miss effects (and score popups) are now all made ready while the song counts in, instead of being set up mid-song whenever several notes were hit at once
- No more stutters from the game trying to reconnect to the server during a song you play alone (it reconnects when the song is over), or from menu music being downloaded and checked in the background while you play
- Names no longer stay old after someone changes their Discord name: the Spectate tab, lobbies, chat and your own name in the menu show the new one
