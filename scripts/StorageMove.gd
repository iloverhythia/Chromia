extends Node

# Settings > Move maps & replays (computers): the big folders (maps, packs,
# replays...) moved to another folder or drive, for players with lots of maps
# and little room left where Chromia's data folder is.
#
# The data folder itself stays (its name is set when the game is built:
# DataFolder.gd); these folders in it are links (directory junctions on
# Windows) to wherever the files really are, so the game keeps using the same
# paths. A move:
#   1. copies every file to the new place (on a thread, with progress; Cancel
#      or any failure removes the copy and changes nothing),
#   2. checks the copy has every file at the same size,
#   3. points the links at the new place,
#   4. deletes the old files (that's the room it frees). Where the old place was
#      the shared SoundSpacePlus folder, a link is left there too, so an older
#      game still finds them.
# Where they are is kept in user://chromia/storage.json.

const FOLDERS := ["maps", "vmaps", "packs", "replays", "content_downloads"]
const STORE := "chromia/storage.json"

static func available() -> bool:
	return OS.has_feature("Windows") and not OS.has_feature("editor")

static func user_dir() -> String:
	return OS.get_user_data_dir()

# where the big folders really are now
static func current_location() -> String:
	var f := File.new()
	var store: String = user_dir().plus_file(STORE)
	if f.file_exists(store) and f.open(store, File.READ) == OK:
		var parsed = JSON.parse(f.get_as_text())
		f.close()
		if parsed.error == OK and parsed.result is Dictionary and String(parsed.result.get("dir", "")) != "":
			return String(parsed.result.dir)
	# moved in from the old shared folder: they're still there, linked (DataFolder.gd)
	var moved: String = user_dir().plus_file(load("res://scripts/DataFolder.gd").MARKER)
	if f.file_exists(moved) and f.open(moved, File.READ) == OK:
		var lines: PoolStringArray = f.get_as_text().split("\n")
		f.close()
		if lines.size() > 2 and lines[2].find("linked") != -1 and Directory.new().dir_exists(lines[0]):
			return lines[0]
	return user_dir()

# ── the move ──
var target := ""
var state := "" # "", "copying", "done", "failed", "cancelled"
var message := ""
var files_done := 0
var files_total := 0
var bytes_done := 0
var bytes_total := 0
var _cancel := false
var _thread: Thread = null

static func start(tree: SceneTree, to: String) -> Node:
	var n = load("res://scripts/StorageMove.gd").new()
	n.name = "StorageMove"
	tree.root.add_child(n)
	n.call_deferred("_begin", to)
	return n

func cancel():
	_cancel = true

func _begin(to: String):
	target = to.replace("\\", "/").trim_suffix("/")
	state = "copying"
	_thread = Thread.new()
	_thread.start(self, "_work", null)

func _process(_dt):
	if _thread != null and state != "copying":
		_thread.wait_to_finish()
		_thread = null

func _exit_tree():
	# (never gone with its thread still running)
	if _thread != null:
		_cancel = true
		_thread.wait_to_finish()
		_thread = null

func _work(_u):
	var from: String = current_location().replace("\\", "/").trim_suffix("/")
	if from.to_lower() == target.to_lower():
		return _end("failed", "They're already there.")
	var d := Directory.new()
	for name in FOLDERS:
		if (target + "/").to_lower().begins_with((from.plus_file(name) + "/").to_lower()):
			return _end("failed", "Pick a folder outside your %s folder." % name)
	if d.make_dir_recursive(target) != OK:
		return _end("failed", "Couldn't create %s." % target)
	# what there is to copy
	var todo := []
	for name in FOLDERS:
		var src: String = from.plus_file(name)
		if d.dir_exists(src):
			todo.append(name)
			var c: Array = _measure(src)
			files_total += int(c[0])
			bytes_total += int(c[1])
	# 1. the copy
	for name in todo:
		if not _copy(from.plus_file(name), target.plus_file(name)):
			for n2 in todo:
				_delete_tree(target.plus_file(n2))
			return _end("cancelled" if _cancel else "failed", "Nothing was changed." if _cancel else "%s Nothing was changed (the copy was removed)." % message)
	# 2. every file there, same sizes
	for name in todo:
		var a: Array = _measure(from.plus_file(name))
		var b: Array = _measure(target.plus_file(name))
		if int(a[0]) != int(b[0]) or int(a[1]) != int(b[1]):
			for n2 in todo:
				_delete_tree(target.plus_file(n2))
			return _end("failed", "The copy of %s didn't match, so nothing was changed." % name)
	# 3. the links, 4. the old files
	var user: String = user_dir().replace("\\", "/")
	for name in todo:
		var link: String = user.plus_file(name)
		var old_real: String = from.plus_file(name)
		if from.to_lower() == user.to_lower():
			# (they were really in the data folder: the files go, a link takes their place)
			_delete_tree(link)
		else:
			_unlink(link)
			_delete_tree(old_real)
			# (the old shared folder: a link there too, for an older game)
			if old_real.to_lower().find("/soundspaceplus/") != -1:
				_junction(old_real, target.plus_file(name))
		if not _junction(link, target.plus_file(name)):
			return _end("failed", "The files are in %s, but the link to %s couldn't be made. Tell staff (nothing is lost)." % [target, name])
	var f := File.new()
	if f.open(user.plus_file(STORE), File.WRITE) == OK:
		f.store_string(JSON.print({ "dir": target, "at": OS.get_unix_time() }))
		f.close()
	return _end("done", "Your maps and replays are in %s now." % target)

func _end(st: String, msg: String):
	message = msg
	state = st

# -> [files, bytes] under a folder
func _measure(path: String) -> Array:
	var d := Directory.new()
	if d.open(path) != OK:
		return [0, 0]
	var files := 0
	var bytes := 0
	d.list_dir_begin(true, false)
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			var c: Array = _measure(path.plus_file(name))
			files += int(c[0])
			bytes += int(c[1])
		else:
			var f := File.new()
			if f.open(path.plus_file(name), File.READ) == OK:
				bytes += f.get_len()
				f.close()
			files += 1
		name = d.get_next()
	d.list_dir_end()
	return [files, bytes]

func _copy(from: String, to: String) -> bool:
	var d := Directory.new()
	if d.open(from) != OK:
		message = "Couldn't read %s." % from
		return false
	if Directory.new().make_dir_recursive(to) != OK:
		message = "Couldn't create %s." % to
		return false
	d.list_dir_begin(true, false)
	var name := d.get_next()
	var ok := true
	while name != "" and ok:
		if _cancel:
			ok = false
			break
		var src: String = from.plus_file(name)
		var dst: String = to.plus_file(name)
		if d.current_is_dir():
			ok = _copy(src, dst)
		else:
			var size := 0
			var f := File.new()
			if f.open(src, File.READ) == OK:
				size = f.get_len()
				f.close()
			if d.copy(src, dst) != OK:
				message = "Couldn't copy %s (is the drive full?)." % name
				ok = false
				break
			files_done += 1
			bytes_done += size
		name = d.get_next()
	d.list_dir_end()
	return ok

func _delete_tree(path: String):
	var d := Directory.new()
	if d.open(path) != OK:
		return
	d.list_dir_begin(true, false)
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			_delete_tree(path.plus_file(name))
		else:
			d.remove(path.plus_file(name))
		name = d.get_next()
	d.list_dir_end()
	Directory.new().remove(path)

# a junction goes without touching what it points at
func _unlink(link: String):
	var out := []
	OS.execute("cmd.exe", PoolStringArray(["/c", "rmdir", link.replace("/", "\\")]), true, out)

func _junction(link: String, to: String) -> bool:
	var out := []
	OS.execute("cmd.exe", PoolStringArray(["/c", "mklink", "/J", link.replace("/", "\\"), to.replace("/", "\\")]), true, out)
	return Directory.new().dir_exists(link)
