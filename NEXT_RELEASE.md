# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Leaderboards: spinlock (Spin with the grid following your cursor, the Spin-lock camera preset or any negative HUD Parallax with Spin) has its own choice, under Spin on the website and in the game's leaderboard menu, and its own badge. Spin no longer counts these passes. Passes from before this update stay under Spin
- /share settings (and the Content Browser's settings profiles) now bring your colorset, note mesh and cursor along when they're your own: adding someone's shared settings puts in their colorset and mesh, and their cursor goes on when you pick their profile in Presets
- VR (Meta Quest): the menu does much less work every frame. The settings boxes and mod buttons rest while their page isn't open (about 90 of them were checking themselves every frame), and the map list stops resizing its buttons once they're in place. For a steadier frame rate in the headset's menu
- Settings > Transfer > "Transfer maps only": send your maps to another device on the same Wi-Fi with a code, without your settings. Only the maps the other device doesn't have yet are sent, the transfer runs in the background so neither game lags, and the maps show up in the map list as they arrive (no restart)
- Replays: the bar you scrub with has a red mark at each miss, like the website's replay viewer, so you can jump straight to them
- Backgrounds: Contours, Lilac Orbit, Aurora and Pulse Floor are replaced by four new ones, each with colours of its own: Deep Sea (light shafts, bubbles and rippling light on the sea floor), Molten Core (a plain of glowing lava cracks under a smoky red sky, embers rising), Nebula (glowing clouds of magenta, blue and teal gas, twinkling stars and a ringed planet) and Crystal Cave (floating crystals shimmering in aqua, violet and rose, with sparkles). If you had one of the old ones picked, you get one of the new ones instead
