extends Node

# Updates for builds that can't replace their own files (iOS): a newer game
# pack (chromia-ios.pck from the latest release) is downloaded into the user
# folder by Online.gd, and loaded here on top of the installed one.
#
# This is the first autoload, and _init runs before the other autoload scripts
# are even loaded, so all of the game (scripts, scenes, assets) comes from the
# newer pack. Project settings and the engine itself only change with a new
# app install.
#
# If a start with a downloaded pack never reaches the menu, the next start
# deletes it and runs the installed version.

const DIR := "user://pack_update"
const PACK := DIR + "/chromia.pck"
const VERSION_FILE := DIR + "/version.txt"
const BOOT_FILE := DIR + "/booting.txt"
const BAD_FILE := DIR + "/bad_version.txt" # an update that failed to start; not offered again

var loaded_version: String = "" # the pack's version when one was loaded
var discarded_version: String = "" # an update that failed to start and was removed this start

static func supported() -> bool:
	# (the Meta Horizon Store version is updated by the store)
	return OS.has_feature("iOS") or (OS.has_feature("quest") and not OS.has_feature("store"))

func _init():
	# (computers: Chromia's own data folder, filled from the old shared one the
	# first time, before anything else reads it)
	load("res://scripts/DataFolder.gd").migrate()
	if not supported():
		return
	var f := File.new()
	var d := Directory.new()
	if f.file_exists(BOOT_FILE):
		# the last starts with the downloaded pack didn't get to the menu
		# (scripts/PackGuard.gd allows a few interrupted starts first)
		if f.open(VERSION_FILE, File.READ) == OK:
			discarded_version = f.get_as_text().strip_edges()
			f.close()
			if discarded_version != "" and f.open(BAD_FILE, File.WRITE) == OK:
				f.store_string(discarded_version)
				f.close()
		_remove_all()
		return
	if not f.file_exists(PACK) or not f.file_exists(VERSION_FILE):
		return
	if f.open(VERSION_FILE, File.READ) != OK:
		return
	var tag := f.get_as_text().strip_edges()
	f.close()
	var installed := String(ProjectSettings.get_setting("application/config/version"))
	if pack_outdated(tag, installed):
		# the installed app is as new or newer (it was reinstalled)
		_remove_all()
		return
	if f.open(BOOT_FILE, File.WRITE) == OK:
		f.store_string(tag)
		f.close()
	if ProjectSettings.load_resource_pack(PACK, true):
		loaded_version = tag
		ProjectSettings.set_setting("application/config/version", tag)
		print("[pack update] running %s (installed app: %s)" % [tag, installed])
	else:
		_remove_all()

# The menu opened: the game works with this pack.
func boot_ok():
	Directory.new().remove(BOOT_FILE)

func _remove_all():
	var d := Directory.new()
	d.remove(BOOT_FILE)
	d.remove(PACK)
	d.remove(VERSION_FILE)

const MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

# (Online.gd: this installed app keeps a downloaded test build. Older apps
# don't have this and drop one at the next start.)
const KEEPS_TEST_PACKS := true

static func is_test_version(v: String) -> bool:
	return v.to_lower().begins_with("test-")

# The downloaded pack is no newer than the installed app (it was reinstalled).
# A test build ("test-nov11-123") and a release ("nov11-2026-a") are told
# apart by their dates only: test builds used to sort before every release,
# so a phone with a release installed dropped every test build it downloaded
# and downloaded it again (stable <-> test, over and over).
static func pack_outdated(tag: String, installed: String) -> bool:
	if tag == installed:
		return true
	if is_test_version(tag) != is_test_version(installed):
		var a := _version_key(tag)
		var b := _version_key(installed)
		for i in range(3):
			if a[i] != b[i]:
				return a[i] < b[i]
		return false # (the same day: the one they downloaded)
	return compare_versions(tag, installed) <= 0

# "oct20-2026-s" -> [2026, 10, 20, "s"]; "test-nov11-123" -> [<year>, 11, 11,
# "123"] (the year isn't in it: the latest one that isn't in the future);
# unknown formats sort first.
static func _version_key(v: String) -> Array:
	var parts := v.to_lower().split("-")
	if parts.size() == 3 and parts[0] == "test" and parts[1].length() >= 4:
		var tm: int = MONTHS.find(parts[1].substr(0, 3)) + 1
		var td: int = int(parts[1].substr(3))
		var now: Dictionary = OS.get_date(true)
		var ty: int = int(now.year)
		if tm > int(now.month) or (tm == int(now.month) and td > int(now.day)):
			ty -= 1
		return [ty, tm, td, parts[2]]
	if parts.size() < 3 or parts[0].length() < 4:
		return [0, 0, 0, ""]
	var month := MONTHS.find(parts[0].substr(0, 3)) + 1
	var day := int(parts[0].substr(3))
	var letter := parts[2] if parts.size() == 3 else PoolStringArray(Array(parts).slice(2, parts.size() - 1)).join("-")
	return [int(parts[1]), month, day, letter]

# <0 if a is older than b, 0 if the same, >0 if newer.
static func compare_versions(a: String, b: String) -> int:
	var ka := _version_key(a)
	var kb := _version_key(b)
	for i in range(3):
		if ka[i] != kb[i]:
			return 1 if ka[i] > kb[i] else -1
	var la: String = ka[3]
	var lb: String = kb[3]
	if la == lb:
		return 0
	if la.length() != lb.length():
		return 1 if la.length() > lb.length() else -1
	return 1 if la > lb else -1
