extends Reference

# iOS updates (see PackUpdate.gd): PackUpdate deletes a downloaded update when
# the start before didn't reach the menu. That also happened when a start was
# only interrupted (the app closed during loading or while an update
# downloaded), which put players back on the version of their installed .ipa.
#
# This file comes from the downloaded pack, so it works with any installed app:
# once the game's scripts run, a start only counts against the update if
# MAX_TRIES starts of it in a row never reached the menu.

const DIR := "user://pack_update"
const BOOT_FILE := DIR + "/booting.txt" # PackUpdate deletes the update when this exists at start
const TRIES_FILE := DIR + "/tries.txt" # "<version> <starts that haven't reached the menu>"
const MAX_TRIES := 3

static func _read(path: String) -> String:
	var f := File.new()
	if not f.file_exists(path) or f.open(path, File.READ) != OK:
		return ""
	var t := f.get_as_text().strip_edges()
	f.close()
	return t

static func _write(path: String, text: String):
	var f := File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()

# A start running the downloaded update `tag` got as far as the game scripts.
static func started(tag: String):
	if tag == "":
		return
	var parts := _read(TRIES_FILE).split(" ")
	var n := 1
	if parts.size() == 2 and parts[0] == tag:
		n = int(parts[1]) + 1
	_write(TRIES_FILE, "%s %d" % [tag, n])
	if n < MAX_TRIES:
		# not the last try yet: if this start gets cut short, keep the update
		Directory.new().remove(BOOT_FILE)

# The menu opened.
static func ok():
	var d := Directory.new()
	d.remove(BOOT_FILE)
	d.remove(TRIES_FILE)

# A new update was just downloaded: it hasn't been tried yet, and this start
# (which got far enough to download it) shouldn't count against it.
static func fresh_download():
	ok()
