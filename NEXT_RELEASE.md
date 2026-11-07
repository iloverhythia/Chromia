# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Fixed the cursor trail crashing the game in VR and sometimes not showing: Smart Trail is now drawn as one object instead of a new one for every piece (smoother on PC too)
- Settings > Video & Audio: No Delay (Experimental, PC) removes mouse movement delay in maps: every mouse movement is used as soon as it comes in, and VSync, the FPS cap and the Windows compositor's extra frame are off while you play (yours come back after the map)
- Settings > Replays & Misc > Experimental: Legacy Mouse Movement moves the cursor with the mouse the way Chromia's very first update did (its original mouse code)
- New modifier: Reverse. The map plays backwards, and so does the song (the first time you play a song with it, it takes a few seconds to turn the song around). Plays with Reverse are never ranked
- The settings preview plays the map you have selected (its notes at your speed mod), and in time with the music when you play the map's music in the menu
- Star ratings follow your speed: a 10 star map at 0.74x shows 7.40 stars
- VR: type with both hands on the keyboard at once (each hand's trigger types the key it points at, straight away)
- Leaderboards by device: every leaderboard in the game (the global one and each map's) has a dropdown for All devices, PC, VR, Quest, Spin or Phone, and so does each map's page on the website
- Each map's leaderboard shows the SP of every pass again (it showed 0)
- Background Editor: right-click a layer > Move to Space puts the picture in the song's world, behind the grid (it moves with the camera), with a Distance slider for how far away it stands
- The cursor trail is smooth on phones (iOS especially): it fades evenly instead of in steps, curves with your swipe instead of in straight pieces, and doesn't get cut short on fast swipes
- Spectate: "N watching" sits in the very bottom-left corner of a player's card and the ••• button is smaller, so they no longer overlap
- VR: four new hands in Settings > VR > Hands: Cartoon glove, Robot, Skeleton and Crystal (spectators see them too)
- Multiplayer: the leaderboard during a match looks like the Online menu (a card per player with their place, picture, accuracy, misses, host / done / failed badges and score), and in VR it shows on a panel beside the left grid panel
- Spectating opens faster: the song starts loading as soon as you click, it no longer waits up to 4 seconds for the player's files (a custom border always made it wait the full time, and never showed), their background pictures and videos come in while you watch, and the setting warnings don't stop it
- Multiplayer: invite people into your lobby. In a lobby, press Invite players (or open the Spectate window) and pick Invite to your lobby from someone's ••• menu; they're asked if they want to join (during a song, right after it). Settings > Online > Allow Lobby Invites turns invites to you off
- VR: the first seconds of a map no longer lag. The hit and miss effects are ready before the first note (in VR they were made on the first hits, a stall every map), the music isn't restarted over small timing blips while the headset is busy loading, ranked maps no longer work out their fingerprint during the first seconds, and on PC VR the cheat scan waits until the song has settled
- Cards: a Cards button under your name on your profile picks your card, the background and border colour of your player card in the Spectate grid (and the border of your website profile). Everyone has Default; special cards unlock in secret ways (Admin, Developer and DJ go to who they're named for). Got a secret code? Type it in the Cards menu
- New Grid Map List option (Settings, or Filters > View > grid): your maps as a grid of square covers, fast even with thousands of maps, switches on and off right away
- Multiplayer: the leaderboard while playing is much smaller (top left corner), no longer glitches, and Tab hides or shows it
- Multiplayer: less lag during matches (the leaderboard no longer rebuilds itself on every note)
- Lobby invites: no more big popup. A small notice in the bottom right says who invited you (Join or Later), the Online tab gets a dot, and the Online page lists your invites
- Invite players in a lobby opens its own list of everyone online with an Invite button each (no longer the Spectate window)
- Multiplayer: the host has a new Pick map button in the lobby that opens its own map list (search, difficulty buttons, covers, stars) to choose the lobby's map
- Chat: type /share to share the map you have selected (or /share and a map's name). It shows as the map's name in blue: click it to download the map and open it ready to play, also from the Spectate window while watching someone. /share colorset, settings, skin, mesh, cursor and hitsound work as before
- Frames: a new Frames button next to Cards on your profile. Pick a frame for your profile picture; it shows in the Spectate grid, Online players, profiles and on the website. Admin has a gold crown, Developer circuit lines, DJ headphones with moving sound bars; every card you unlock gives you its frame
- Badges on profiles (in the game and on the website) are now simple one-colour icons
- VR: every slider in Settings > VR (grip, grid, menu screen, aim, haptics...) has - and + buttons beside it that move it one step (hold to keep going). The sliders no longer get pushed to the end by the thumbstick after you drag one
- VR: new Grid size setting (Settings > VR > In songs): makes the grid, notes and cursor bigger, from the default size up to double
- Menu Customizer (Settings > Menu Customizer): pick your own colours for the menu's buttons, text, text boxes and sidebar, button roundness and borders, and a background pattern (contour lines, grid, dots, waves, hexagons, stripes, stars or a plain colour) with your colours and speed. Exporting a skin now takes your menu with it
- New modifier: Harder Rock. Like Hard Rock but the notes spread even further out, your cursor can go further past the grid and the hit window is tighter. Turning it on turns Hard Rock off (and the other way round)
- The modifiers on the map screen are on pages now (3 rows at a time): the arrows or the mouse wheel turn the page, the dots jump to a page, and a page with a modifier on has a green dot
- Moving profile pictures and banners: upload a GIF on the website and it moves in the game too (Spectate, Online players, profiles)
- Website: you can now comment on maps on their map page (sign in with Discord); you can delete your own comments
- Map icons load much faster everywhere (grid, map list, the multiplayer map picker, VR) and no longer make the menu stutter while they load
- The grid map list no longer lags in VR
- Modifiers show 9 per page
- The Stats page opens instantly, even with a big map library (its records summary loads in the background)
