extends Reference

# Settings > Transfer > Settings backups.
# Copies of your settings file, kept in user://settings_backups, so that a
# reset (or a mistake) can't lose them:
#  - Back Up Settings (Rhythia.settings_backup, on from the start): copies are made
#  - Only When Saving a New Profile (Rhythia.settings_backup_profile_only, on
#    from the start): a copy only when you make a new profile (Select Profile >
#    Create New From Current). Off: a copy every time your settings change
#    (a moment after the change, and never twice the same file).
# The newest KEEP copies are kept. "Restore a backup" on the Transfer page
# adds the one you pick as a profile.

const DIR := "user://settings_backups"
const KEEP := 80

static func folder() -> String:
	return Globals.p(DIR)

# every backup, newest first: [{path, name, time}]
static func list() -> Array:
	var out := []
	var d := Directory.new()
	if d.open(folder()) != OK:
		return out
	d.list_dir_begin(true, true)
	var n := d.get_next()
	var f := File.new()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".json"):
			var p: String = folder().plus_file(n)
			out.append({"path": p, "name": n, "time": f.get_modified_time(p)})
		n = d.get_next()
	d.list_dir_end()
	out.sort_custom(load("res://scripts/SettingsBackup.gd"), "_newer")
	return out

static func _newer(a: Dictionary, b: Dictionary) -> bool:
	if a.time == b.time:
		return a.name > b.name
	return a.time > b.time

static func _stamp() -> String:
	var t := OS.get_datetime()
	return "%04d-%02d-%02d %02d.%02d.%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]

# A copy of the settings file `source` in the backups folder. label: what goes
# in its name after the date ("settings", or "profile <name>"). Returns the
# copy's path, or "" when nothing was copied (no such file, not settings, or
# the same as the newest copy when only_if_changed).
static func make(source: String, label: String = "settings", only_if_changed: bool = true) -> String:
	var f := File.new()
	if not f.file_exists(source) or f.open(source, File.READ) != OK:
		return ""
	var text := f.get_as_text()
	f.close()
	var parsed := JSON.parse(text)
	# (never a damaged or empty file: that is what the copies are there against)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY or parsed.result.size() < 5:
		return ""
	var d := Directory.new()
	if not d.dir_exists(folder()):
		d.make_dir_recursive(folder())
	var all := list()
	if only_if_changed and not all.empty() and f.open(all[0].path, File.READ) == OK:
		var same: bool = f.get_as_text() == text
		f.close()
		if same:
			return ""
	var clean := ""
	for i in range(label.length()):
		var c := label[i]
		clean += c if not (c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]) else "_"
	clean = clean.strip_edges()
	if clean == "":
		clean = "settings"
	var path: String = folder().plus_file("%s %s.json" % [_stamp(), clean])
	var n := 2
	while f.file_exists(path):
		path = folder().plus_file("%s %s (%d).json" % [_stamp(), clean, n])
		n += 1
	if f.open(path, File.WRITE) != OK:
		return ""
	f.store_string(text)
	f.close()
	# the oldest go once there are more than KEEP
	all = list()
	for i in range(KEEP, all.size()):
		d.remove(all[i].path)
	return path
