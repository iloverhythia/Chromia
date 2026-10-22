#!/bin/bash
# Turns this checkout into the Meta Quest (standalone VR) project, for the
# "Quest" export preset only (run on a throwaway copy / in CI, never commit
# the result):
#  - the OpenXR plugin (GodotVR/godot_openxr) with its Android libraries, in
#    place of the PC-only SteamVR plugin
#  - Godot's Android build template (OpenXR needs the gradle build)
# Usage: prepare_quest.sh <android_source.zip> <godot-openxr.zip>
set -euo pipefail
src_zip="$1"
oxr_zip="$2"

# OpenXR plugin: only what the Quest needs (no hand models / PC libraries)
tmp=$(mktemp -d)
unzip -q "$oxr_zip" -d "$tmp"
oxr=$(find "$tmp" -type d -path "*addons/godot-openxr" | head -n1)
test -n "$oxr"
rm -rf addons/godot-openxr
mkdir -p addons/godot-openxr/bin/android addons/godot-openxr/config
cp "$oxr"/bin/android/*.so addons/godot-openxr/bin/android/
cp "$oxr"/config/*.gdnlib "$oxr"/config/*.gdns addons/godot-openxr/config/
cp "$oxr"/LICENSE addons/godot-openxr/
# Android entries only (the PC builds keep SteamVR)
python3 - <<'PY'
import re
p = "addons/godot-openxr/config/godot_openxr.gdnlib"
s = open(p).read()
s = "\n".join(l for l in s.split("\n") if not re.match(r"^(Windows|X11|OSX)\.", l))
open(p, "w").write(s)
PY
rm -rf "$tmp"

# project settings: OpenXR as the native singleton, no SteamVR editor plugin
python3 - <<'PY'
import re
p = "project.godot"
s = open(p).read()
s = re.sub(r'^singletons=\[.*\]$', 'singletons=[ "res://addons/godot-openxr/config/godot_openxr.gdnlib" ]', s, flags=re.M)
s = s.replace(', "res://addons/godot-openvr/plugin.cfg"', '').replace('"res://addons/godot-openvr/plugin.cfg", ', '')
# Quest renders with GLES3 (OpenXR on Quest has no GLES2 path here)
s = s.replace("quality/driver/fallback_to_gles2=true", "quality/driver/fallback_to_gles2=false")
# the store wants plain landscape (phones use sensor_landscape)
s = s.replace('window/handheld/orientation="sensor_landscape"', 'window/handheld/orientation="landscape"')
open(p, "w").write(s)
PY
rm -rf addons/godot-openvr

# Android build template (what Godot's "Install Android Build Template" does)
rm -rf android
mkdir -p android/build
unzip -q "$src_zip" -d android/build
echo -n "3.5.3.stable" > android/.build_version
touch android/build/.gdignore
# Meta's OpenXR loader: apps targeting Android 12+ must ask for the headset's
# forward loader, and the Khronos runtime broker must be visible to the app
python3 - <<'PY'
p = "android/build/AndroidManifest.xml"
s = open(p).read()
add = """
    <uses-native-library android:name="libopenxr_forwardloader.oculus.com" android:required="false" />
"""
queries = """
    <queries>
        <provider android:authorities="org.khronos.openxr.runtime_broker;org.khronos.openxr.system_runtime_broker" />
        <intent>
            <action android:name="org.khronos.openxr.OpenXRRuntimeService" />
        </intent>
    </queries>
"""
assert "<application" in s
s = s.replace("<application", queries.strip("\n") + "\n\n    <application", 1)
i = s.index(">", s.index("<application")) + 1
s = s[:i] + add + s[i:]
# the headsets it runs on (the store wants them listed)
s = s.replace('android:name="com.oculus.supportedDevices"\n            android:value="all"', 'android:name="com.oculus.supportedDevices"\n            android:value="quest2|questpro|quest3|quest3s"')
open(p, "w").write(s)
PY
# no release lint (slow, and it downloads extra tools)
cat >> android/build/build.gradle <<'GRADLE'

android {
    lintOptions {
        checkReleaseBuilds false
        abortOnError false
    }
}
GRADLE
echo "Quest project ready"
