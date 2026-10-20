"""Puts the app icon from assets/images/branding/ios into a built Chromia.app.

The .ipa is made on Linux from the last released app (the engine never
changes), so its compiled asset catalog (Assets.car) can't be rebuilt without
Xcode, and iOS kept showing the old icon from it. So the catalog is removed
(it only held that icon and the launch screen's splash image; the launch
screen keeps its background colour), the icon PNGs are written into the app
and Info.plist points at them (CFBundleIconFiles).

Usage: ipa_icons.py <path to Chromia.app> <repo root> [build number]
"""
import os
import plistlib
import shutil
import sys

app, root = sys.argv[1], sys.argv[2]
src = os.path.join(root, "assets", "images", "branding", "ios")
files = {
    "AppIcon60x60@2x.png": "icon_120.png",
    "AppIcon60x60@3x.png": "icon_180.png",
    "AppIcon76x76@2x~ipad.png": "icon_152.png",
    "AppIcon83.5x83.5@2x~ipad.png": "icon_167.png",
}
for dst, name in files.items():
    shutil.copyfile(os.path.join(src, name), os.path.join(app, dst))

car = os.path.join(app, "Assets.car")
if os.path.exists(car):
    os.remove(car)

plist_path = os.path.join(app, "Info.plist")
with open(plist_path, "rb") as f:
    info = plistlib.load(f)
info["CFBundleIcons"] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60"]}}
for key in ("CFBundleIconName", "CFBundleIconFile"):
    info.pop(key, None)
info["CFBundleIconFiles"] = ["AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"]
info["CFBundleIcons~ipad"] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"]}}
# a new build number each release, so iOS refreshes the home screen icon
if len(sys.argv) > 3 and sys.argv[3].isdigit():
    info["CFBundleVersion"] = sys.argv[3]
    info["CFBundleShortVersionString"] = "1.%s" % sys.argv[3]
with open(plist_path, "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
print("app icon written into", app)
