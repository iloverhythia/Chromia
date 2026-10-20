"""Puts the app icon from assets/images/branding/ios into a built Chromia.app.

The .ipa is made on Linux from the last released app (the engine never
changes), so its compiled icon catalog (Assets.car) can't be rebuilt without
Xcode. Instead the icon PNGs are written into the app and Info.plist is
pointed at them (CFBundleIconFiles), which iOS uses when no icon catalog name
is given.

Usage: ipa_icons.py <path to Chromia.app> <repo root>
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

plist_path = os.path.join(app, "Info.plist")
with open(plist_path, "rb") as f:
    info = plistlib.load(f)
info["CFBundleIcons"] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60"]}}
info["CFBundleIcons~ipad"] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"]}}
with open(plist_path, "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_BINARY)
print("app icon written into", app)
