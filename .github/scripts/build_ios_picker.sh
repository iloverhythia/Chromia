#!/bin/bash
# Builds ChromiaPicker.framework (ios/picker: the iPhone file picker, touch
# delay and refresh rate) on Linux
# with clang + lld and the iOS SDK headers/stubs from theos/sdks, into the
# Frameworks folder of the .app given as $1. No Mac needed: the game loads it
# with GDNative (scripts/ui/MobileFilePicker.gd); the sideloading app signs it
# along with the rest of the app.
set -euo pipefail
app="$1"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
# iPhones only draw above 60 Hz for apps that ask for it (Settings > 120 Hz)
python3 - "$app/Info.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read()
fmt = plistlib.FMT_BINARY if data.startswith(b"bplist") else plistlib.FMT_XML
info = plistlib.loads(data)
info["CADisableMinimumFrameDurationOnPhone"] = True
with open(path, "wb") as f:
    plistlib.dump(info, f, fmt=fmt)
PY
command -v ld64.lld > /dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq lld; }
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks "$work/sdks"
(cd "$work/sdks" && git sparse-checkout set --no-cone '/iPhoneOS16.5.sdk/usr/' '/iPhoneOS16.5.sdk/SDKSettings.*' '/iPhoneOS16.5.sdk/System/Library/Frameworks/')
sdk="$work/sdks/iPhoneOS16.5.sdk"
fw="$app/Frameworks/ChromiaPicker.framework"
rm -rf "$fw"
mkdir -p "$fw"
clang -target arm64-apple-ios12.0 -isysroot "$sdk" -fobjc-arc -O2 -Wall -dynamiclib -fuse-ld=lld \
  -install_name @rpath/ChromiaPicker.framework/ChromiaPicker \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -o "$fw/ChromiaPicker" "$repo/ios/picker/ChromiaPicker.m"
cp "$repo/ios/picker/Info.plist" "$fw/Info.plist"
rm -rf "$work"
echo "built $fw"
