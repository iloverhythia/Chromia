#!/bin/bash
# Builds ChromiaPicker.framework (ios/picker, the iPhone file picker) on Linux
# with clang + lld and the iOS SDK headers/stubs from theos/sdks, into the
# Frameworks folder of the .app given as $1. No Mac needed: the game loads it
# with GDNative (scripts/ui/MobileFilePicker.gd); the sideloading app signs it
# along with the rest of the app.
set -euo pipefail
app="$1"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
command -v ld64.lld > /dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq lld; }
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks "$work/sdks"
(cd "$work/sdks" && git sparse-checkout set --no-cone '/iPhoneOS14.5.sdk/usr/' '/iPhoneOS14.5.sdk/SDKSettings.*' '/iPhoneOS14.5.sdk/System/Library/Frameworks/')
sdk="$work/sdks/iPhoneOS14.5.sdk"
fw="$app/Frameworks/ChromiaPicker.framework"
rm -rf "$fw"
mkdir -p "$fw"
clang -target arm64-apple-ios12.0 -isysroot "$sdk" -fobjc-arc -O2 -Wall -dynamiclib -fuse-ld=lld \
  -install_name @rpath/ChromiaPicker.framework/ChromiaPicker \
  -framework UIKit -framework Foundation \
  -o "$fw/ChromiaPicker" "$repo/ios/picker/ChromiaPicker.m"
cp "$repo/ios/picker/Info.plist" "$fw/Info.plist"
rm -rf "$work"
echo "built $fw"
