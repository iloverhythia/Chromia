# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- VR replays watched from the player's eyes use the VR view settings (no camera unlock or parallax, as when spectating someone in VR) and show the player's own hands: yours in your own replays, theirs on Save video links
- VR: breck's snow leopard paw now shows up in Settings > VR > Hands. The game only found out which player you are after you had opened Spectate or Online, so the hand was missing (and, if already picked, shown as the Furry paws). It now asks once right after connecting.
- Save video's Game view can make 120 fps videos (owners only for now)
