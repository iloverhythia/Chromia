# Notes for the next production release

Add one line per change, starting with "- " (players read these in the
update log). Publishing to production turns them into the new version's notes
in scripts/Savia.gd and empties this list.
- Vaporwave (Roblox) background: fixed the lower half of the screen turning solid white (cutting the grid and HUD in half) whenever the camera rose a little, as it does in Spin and with parallax, and the sky turning flat grey when it dipped. The background has two huge paper-thin sheets lying exactly at eye level that were only ever meant to be seen edge-on
- Fixed a way the game could close by itself when a song started right after you picked a map (within about half a second): picking a map started a background check of its song that read in a script at the same moment the song's loading did
- A quick second click on a map in the list starts it the same way the Play button does (it had its own way in). The same click arriving twice no longer counts as a second click
- VR (Meta Quest): the game no longer lowers your refresh rate by itself. With Frame Smoothing on it used to drop a headset from 120 Hz to 90 or 72 after a song with late frames and keep it there for many songs; a rate held that way is let go of. If you want it, it's a switch now: Settings > VR > Graphics > "Lower the refresh rate by itself when songs keep dropping frames"
- VR (Meta Quest): Refresh rate has a 240 Hz entry. It asks the headset for 240 Hz even though the headset doesn't list it, and tells you whether the headset took it or which rate it is really at
- VR (Meta Quest): a headset that keeps refusing the refresh rate asked for (another app holding it, for one) is no longer asked again every five seconds, which could cost a hitch each time; after three refusals it's left alone for a minute
- VR (Meta Quest): Settings > VR > Graphics > "Set up for the best frame rate": one press for foveated rendering High, glow off, the simple background, and render resolution back to 100% if it was higher
- Every pass now saves your display settings to the server (even with spectators off), so replays of your passes on the website play with your settings
- Meta Quest and phones: the background check of a picked map's song (new in the last update) is off there for now. Two Quest reports ended seconds after a map was picked in the menu, which is when it ran
- Meta Quest and phones: fixed a stutter every ten seconds during songs that came with the last update. The game notes every ten seconds that it is still running (for crash reports), and wrote that note to the device's storage in the middle of the song; it's written on the side now. The note about a slow frame doesn't go to the storage right after the slow frame either
- Android phones: the file browser can see your files again (songs, maps, pictures in Downloads and other folders). On Android 11 and later it showed folders but no files. Tap the new "Allow file access" button in the file browser, turn on "Allow access to manage all files" for Chromia, and come back. You need to install this version's chromia-android.apk for it.
- VR (Meta Quest): closing the game from the headset's own menu is no longer taken for a crash (no crash notice at the next start, no report sent). The game now notes when the headset's menu opens over it and when it gets the focus back.
