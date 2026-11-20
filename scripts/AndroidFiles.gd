extends Reference

# Android phones and tablets (the chromia-android.apk build, feature "allfiles"):
# what the game may read outside its own folder.
#
# The build targets Android 13, where the old storage permission
# (READ_EXTERNAL_STORAGE) can no longer be granted: without more, the file
# browser saw folders but none of the files in them. The build now also asks
# for "All files access" (MANAGE_EXTERNAL_STORAGE), which the player turns on
# in a system settings screen. OS.request_permissions() opens that screen each
# time it is called while the access is off, so it is only called when the
# player taps "Allow file access" in the file browser, never at startup
# (Android 11 and later).
# Not for the Meta Quest builds: their manifest doesn't have the permission.

const ALL_FILES := "android.permission.MANAGE_EXTERNAL_STORAGE"
const READ := "android.permission.READ_EXTERNAL_STORAGE"

static func has_all_files_build() -> bool:
	return OS.has_feature("Android") and OS.has_feature("allfiles")

# Android's API level (30 = Android 11), 0 when it can't be found out
static func sdk() -> int:
	if Engine.has_meta("android_sdk"):
		return int(Engine.get_meta("android_sdk"))
	var v := 0
	if OS.has_feature("Android"):
		var out := []
		if OS.execute("/system/bin/getprop", ["ro.build.version.sdk"], true, out) == OK and out.size() > 0:
			var txt := String(out[0]).strip_edges()
			if txt.is_valid_integer():
				v = int(txt)
	Engine.set_meta("android_sdk", v)
	return v

# Is there something the player still has to allow before every file shows?
static func needs_access() -> bool:
	if not has_all_files_build():
		return false
	var granted := OS.get_granted_permissions()
	var level := sdk()
	if level > 0 and level < 30:
		# Android 10 and older: the ordinary storage permission is all there is
		return not (READ in granted)
	return not (ALL_FILES in granted)

# Startup: may the game ask for its permissions now, without a tap?
# (Meta Quest and older builds: yes, as before.)
static func ask_at_start_ok() -> bool:
	if not has_all_files_build():
		return true
	var level := sdk()
	if level > 0 and level < 30:
		return true
	# Android 11+: asking would open the "All files access" settings screen
	# over the game at every start until it's on. The file browser asks.
	return ALL_FILES in OS.get_granted_permissions()

# The player asked for it (the file browser's button)
static func ask():
	OS.request_permissions()
