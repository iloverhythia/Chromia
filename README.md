# Installing Chromia

Chromia runs on Windows, Linux, macOS, Android, iPhone and iPad, Meta Quest headsets, and in a web browser. It is free on every one of them.

Every download is on the **[latest release page](https://github.com/iloverhythia/Chromia/releases/latest)**. Scroll to **Assets** at the bottom of the release and pick the file for your device:

| Device | File to download |
|---|---|
| Windows | `chromia-windows.zip` |
| Linux | `chromia-linux.zip` |
| macOS | `chromia-macos.zip` |
| Android phone or tablet | `chromia-android.apk` |
| iPhone / iPad | `chromia-ios.ipa` |
| Meta Quest 2, Pro, 3, 3S | `chromia-quest.apk` |
| Any browser | nothing to download: [play here](https://iloverhythia.github.io/Chromia/) |

You don't need the other files in the list (`.pck`, `-compat.txt`, `chromia-web.zip`). The game uses those to update itself.

---

## Windows

1. Download `chromia-windows.zip`.
2. Right-click it and choose **Extract All**. Put the folder somewhere you can write to, such as Documents or the Desktop (not Program Files).
3. Open the folder and run **Chromia.exe**.

If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**. This appears because the game isn't signed with a paid certificate.

Keep `Chromia.exe` and `Chromia.pck` together in the same folder. The game updates itself when a new version is out.

**PC VR:** the Windows version also plays in VR through SteamVR. Start SteamVR with your headset connected, open Chromia, and press the headset button on the left sidebar.

## Linux

1. Download `chromia-linux.zip` and unzip it.
2. Make the game runnable, then start it:
   ```
   chmod +x Chromia.x86_64
   ./Chromia.x86_64
   ```

Keep `Chromia.x86_64` and `Chromia.pck` in the same folder. The game updates itself.

## macOS

1. Download `chromia-macos.zip` and double-click it to unzip.
2. Move **Chromia.app** to your Applications folder (optional).
3. The first time, right-click **Chromia.app** and choose **Open**, then **Open** again in the box that appears.

If macOS still refuses to open it, go to **System Settings > Privacy & Security**, scroll down to the message about Chromia, and click **Open Anyway**. This is only needed once.

## Android

1. On your phone, download `chromia-android.apk`.
2. Tap the downloaded file. Android asks whether your browser or files app may install apps: tap **Settings**, turn on **Allow from this source**, and go back.
3. Tap **Install**, then **Open**.

To update, download the newer `chromia-android.apk` and install it over the old one. Your maps, scores and settings stay.

## iPhone and iPad

Chromia isn't on the App Store, so it is installed with a sideloading app from a computer.

1. On your computer, install [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io).
2. Download `chromia-ios.ipa`.
3. Connect your iPhone or iPad and install the `.ipa` with the sideloading app, signing in with your Apple ID when asked.
4. On the device, go to **Settings > General > VPN & Device Management**, tap your Apple ID, and tap **Trust**.
5. On iOS 16 or later, also turn on **Settings > Privacy & Security > Developer Mode** and restart when asked.

With a free Apple ID, sideloaded apps stop opening after 7 days until you refresh them with the same sideloading app. Your data stays when you refresh.

Chromia updates itself inside the app. Now and then an update needs the new `.ipa` installed again; the game tells you when.

No computer? Use the [browser version](https://iloverhythia.github.io/Chromia/) in Safari instead.

## Meta Quest (2, Pro, 3, 3S)

The Quest version runs on the headset by itself, no PC needed while playing. It is installed once from a computer or phone.

**Before you start:** turn on Developer Mode. In the Meta Horizon phone app, open **Menu > Devices**, pick your headset, then **Headset settings > Developer Mode**, and switch it on. (Meta asks you to create a free developer account the first time.)

**With SideQuest (easiest):**

1. Install [SideQuest](https://sidequestvr.com/setup-howto) on your computer.
2. Connect the headset with a USB cable. Put the headset on and choose **Allow** when it asks about USB debugging.
3. Download `chromia-quest.apk`, then drag it onto the SideQuest window (or use the **Install APK file from folder** button at the top).

**With adb:**

```
adb install -r chromia-quest.apk
```

**To play:** in the headset, open your **Library**, set the filter at the top to **Unknown Sources**, and choose **Chromia**. It starts straight in VR and updates itself.

## Browser

Open **https://iloverhythia.github.io/Chromia/** in Chrome, Edge, Firefox or Safari. There is nothing to install, and it works on phones too.

The browser version is the quickest way to try the game. The installed versions run better and keep your maps on your device.

---

## Updates and test builds

- Windows, Linux, iPhone / iPad and Meta Quest update themselves.
- Android updates by installing the newer `.apk` over the old one.
- Want new features early? In the game, go to **Settings > Update channel** and pick **Test**. Test builds come out often and can have bugs; switch back to **Stable** at any time.

## Problems?

Ask in the [Chromia Discord server](https://discord.gg/chromiagame). If the game closes by itself, it offers to send a crash report the next time you open it; sending it helps get the problem fixed.
