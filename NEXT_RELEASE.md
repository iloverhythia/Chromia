# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- VR / phones: .rhm maps from rhythia.com (Content Browser) convert properly: they were converted without their music (and then wouldn't play) because the audio was looked for in the wrong folder
- VR: pressing Start after Random starts the map (the Random button could stay held, so Start picked another map instead)
- Spectating: you hear the hit and miss sounds of the player you watch (there were none)
- VR: while you watch someone, a panel above the right side says who it is and how to stop (hold your give up button); the Following / Stop bar shows on the menu screen in the headset
- Map editor is much faster: placing, deleting and moving notes on big maps no longer freezes for a moment (about 30 times quicker on a 20,000-note map, undo/redo too), and playing the song in the editor no longer slows every frame down
- Your Online status shows you playing again while you're in a map (it errored and wasn't sent)
- Map screen: a Leaderboard tab (next to Best and History) on ranked maps shows everyone's best pass, top first: their picture, SP, accuracy, misses and speed (click someone to open their profile)
- VR: move the keyboard anywhere on the menu screen by dragging the bar along its top; it stays where you put it (Reset in the bar puts it back)
- VR: a Height setting (Settings > VR > Height) raises or lowers you up to 1 m, in the menu and in songs
- Fixed the in-game HUD failing to load in the last test builds (two features had a function with the same name)
- VR: a new Ball hand (Settings > VR > Hands): a plain round white sphere for each hand (spectators see it too)
- Settings: the grid's Borders moved to the Background Editor tab
- Background Editor > HUD panels: pick how the side panels look while you play (Chromia, Sound Space, Outlined, Glass, No background, or your own picture) and how big they are (50% to 200%). Spectators see your style and size
- Settings > Fonts: a Size slider for the HUD's text (50% to 200%), seen by spectators too
- Settings > Video & Audio: Fullscreen is now called Exclusive Fullscreen (the true fullscreen, run by your graphics driver), and it and Borderless Windowed turn each other off; F11 / Alt+Enter leaves Borderless Windowed first
- Spectate: right-click someone's card for View stats (their level, XP, SP and places, passes, bio and best plays), Spectate, or their profile on the website
- Settings > Keybinds: turn any keybind off with its On box, or all of them with Turn all keybinds off (their keys and controller buttons do nothing); turning one back on restores your key
- Player Avatar editor works again and is easier to use: tick items instead of typing their names, with new ones (top hat, cap, crown, cat ears, horns, halo, glasses, bow, scarf, tie, bow tie, cape), colours for the head, body and eyes, drag to turn your avatar, and it's saved. The Back button works again. Your avatar shows in replays with the alternate camera, and people watching you with your settings see it
- Spectating: 3rd person view. In VR press B / Y while you watch someone: you move behind and beside them and see their avatar play (the avatar from their Player Avatar editor). On PC press 3. Replays: press 3 to switch to the avatar camera
- VR: the intro cutscene never plays in VR (on the Quest it used to play every time the game opened); the Replay Intro button says so instead
- Maps with WAV music (some rhythia.com downloads) play their music: they said the audio was broken. WAV files with extra sections (JUNK, LIST...) and 8, 24 and 32-bit ones work too
- Spectating with their settings no longer shows bits of your own: colours, note shapes, effects or backgrounds you don't have fall back to the defaults instead of yours, and their HUD options (stats, config, avatar, panels) are used too
- Spectating: following someone keeps watching them when they restart a map (it used to stop)
- Background Editor: a Background brightness slider darkens the background behind the notes (notes and HUD stay bright)
- VR: the Ball hand is white now in every scene (it looked grey in dark spaces and menus)
- Background Editor: add .mp4, .mov, .mkv, .avi and other videos (the Chromia server turns them into .webm for you, no sound, up to 2 minutes; you can close the settings while it works). GIFs move, and .webm / .ogv are added as they are
- Chromia skins (.cskin): Settings > Skins exports everything you have on into one file (your look settings, colorset, note mesh, border, hit and miss sounds, cursor and trail pictures, sounds, backgrounds and Background Editor layers, HUD font and panel picture, avatar, VR hands) for others to import. Putting one on keeps your old look as "Before <skin>" in My skins so you can go back. You can also drop a .cskin on the game window
- Online page redone: a clear "Play together" section (Host a lobby, Public, join with a friend's code), public lobbies always listed with Refresh, and inside a lobby a big lobby code with Copy, the map, players as cards (ready / checking / downloading the map, HOST) and Start / Leave. Same look as the Spectate window
- The Spectate window opens smoothly (it no longer stutters while it fills in)
- Menu music is back: the seven menu songs play again. They're downloaded from the Chromia server the first time (about 15 MB, once) instead of making every download bigger, and then play from your game's cache, offline too
- VR: Settings > VR > Controller grip > Calibrate: a dot shows in front of you; hold the controller the way you normally play, point at it and hold the trigger for a second, and the grip's tilt and turn are set so the beam goes where your hand points (either hand; B / Y cancels)
- Content Browser: a Hit Sounds tab. Play one to hear it, Use it to make it your hit sound, or share yours / upload a file (.ogg, .mp3, .wav)
- Content Browser > Maps > Chromia players: every map on the Chromia server is listed too (ranked ones say Ranked), ready to download
- Fixed the Ranked filter leaving out ranked maps whose id has capitals, spaces or signs like . ! ( ) (for example the Trrricksters!! map)
- Online > Admin (staff only) in the same look as the rest of the Online page, and bigger Lobby / Admin tabs
