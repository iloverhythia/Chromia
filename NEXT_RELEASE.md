# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.

- Scores now remember if they were played in VR or on a phone/tablet (the website shows VR / Mobile / Spin badges)
- Settings > Update channel: switch to test builds (new things first, on the test server) or back to stable
- Ranked passes are sent with their replay (needed for XP now, and anyone can watch them on the website). Replays are recorded even with Record Replays off; those are deleted again when you're back in the menu
