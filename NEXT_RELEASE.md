# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Leaderboards: spinlock (Spin with the grid following your cursor, the Spin-lock camera preset or any negative HUD Parallax with Spin) has its own choice, under Spin on the website and in the game's leaderboard menu, and its own badge. Spin no longer counts these passes. Passes from before this update stay under Spin
- /share settings (and the Content Browser's settings profiles) now bring your colorset, note mesh and cursor along when they're your own: adding someone's shared settings puts in their colorset and mesh, and their cursor goes on when you pick their profile in Presets
