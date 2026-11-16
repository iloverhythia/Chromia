extends Node

# Your bests (every pass and attempt) for Rhythia Nightly and other older
# clients, which use the old shared "SoundSpacePlus" folder.
#
# Chromia saved its bests there in its newer file format (version 4, with a
# date on each best) before it had its own folder (DataFolder.gd). Older
# clients only read up to version 3, so to them those files looked broken:
# the bests were gone, and the next one was saved over them. And bests made
# since then are only in Chromia's own folder (user://chromia/bests).
#
# So once, on a computer with its own Chromia folder, every map's bests in
# SoundSpacePlus\bests are put together with Chromia's (for each mod / speed,
# the better of the two, as Song.is_pb_better picks) and written as version 3:
# the same bests without the dates. A file in the old folder is only rewritten
# when that changes something, and is kept as it was in
# user://chromia/old_folder_bests first. Chromia's own bests aren't touched.

const OLD_NAME := "SoundSpacePlus"
const MARKER := "user://chromia/old_folder_bests_synced.txt"
const KEEP_DIR := "user://chromia/old_folder_bests"
const OWN_BESTS := "user://chromia/bests"
const SIG := [83, 83, 43, 112, 66] # "SS+pB"

var _thread: Thread = null
var _args := {}

# (Savia.gd, at startup)
static func start(parent: Node):
	if not (OS.has_feature("Windows") or OS.has_feature("X11") or OS.has_feature("OSX")) or OS.has_feature("editor"):
		return
	var own: String = OS.get_user_data_dir()
	if own.get_file() == OLD_NAME:
		return # (a build still on the shared folder: its bests are in chromia/bests there)
	var old_root: String = own.get_base_dir().plus_file(OLD_NAME)
	if File.new().file_exists(Globals.p(MARKER)) or not Directory.new().dir_exists(old_root):
		return
	var n = load("res://scripts/OldFolderBests.gd").new()
	n.name = "OldFolderBests"
	n._args = {old = old_root.plus_file("bests"), own = Globals.p(OWN_BESTS), keep = Globals.p(KEEP_DIR)}
	parent.call_deferred("add_child", n) # (the game is still starting up)

func _ready():
	if OS.can_use_threads():
		_thread = Thread.new()
		if _thread.start(self, "_job", _args) == OK:
			return
		_thread = null
	_done(_job(_args))

func _process(_d):
	if _thread != null and not _thread.is_alive():
		_done(_thread.wait_to_finish())
		_thread = null

func _exit_tree():
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func _done(res):
	var f := File.new()
	Directory.new().make_dir_recursive(Globals.p("user://chromia"))
	if f.open(Globals.p(MARKER), File.WRITE) == OK:
		f.store_string("%d\n%s\n" % [OS.get_unix_time(), String(res)])
		f.close()
	print("[old folder bests] %s" % String(res))
	queue_free()

# the bests files in a folder (map ids: no .bak, .tmp, .unreadable-...)
static func _ids(dir_path: String) -> Array:
	var out := []
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return out
	d.list_dir_begin(true, true)
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.get_extension() == "" and fn.find(".unreadable-") == -1:
			out.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	return out

func _job(a: Dictionary) -> String:
	Directory.new().make_dir_recursive(a.old)
	var ids := {}
	for id in _ids(a.old): ids[id] = true
	for id in _ids(a.own): ids[id] = true
	var written := 0
	var failed := 0
	for id in ids.keys():
		var r := _sync(a.old.plus_file(id), a.own.plus_file(id), a.keep.plus_file(id))
		if r == 1: written += 1
		elif r == -1: failed += 1
	return "%d maps' bests written for older clients (of %d), %d couldn't be" % [written, ids.size(), failed]

# a bests file -> { version, rows: { key: best } }, or {} when it can't be read
static func _read(path: String) -> Dictionary:
	var f := File.new()
	if not f.file_exists(path) or f.open(path, File.READ) != OK:
		return {}
	if f.get_len() < 15 or f.get_buffer(5) != PoolByteArray(SIG):
		f.close()
		return {}
	var sv: int = f.get_16()
	if sv > 4:
		f.close()
		return {}
	var amt: int = f.get_64()
	var rows := {}
	for i in range(amt):
		if f.eof_reached():
			f.close()
			return {} # (damaged)
		var pb := {}
		var key: String = f.get_line()
		pb.has_passed = bool(f.get_8())
		pb.pauses = f.get_16()
		pb.hit_notes = f.get_32()
		pb.total_notes = f.get_32()
		pb.position = f.get_32()
		pb.length = f.get_32()
		pb.max_combo = f.get_16() if sv >= 3 else 65535
		if sv >= 4: f.get_64() # (the date: version 3 has none)
		rows[key] = pb
	var damaged := f.eof_reached() # (a read ran past the end)
	f.close()
	if damaged:
		return {}
	return {version = sv, rows = rows}

# the same order as Song.is_pb_better: is `pb` better than `ob`?
static func _better(ob: Dictionary, pb: Dictionary) -> bool:
	if int(pb.has_passed) != int(ob.has_passed):
		return int(pb.has_passed) > int(ob.has_passed)
	if not pb.has_passed and pb.position != ob.position:
		return pb.position > ob.position
	var pbm: int = pb.total_notes - pb.hit_notes
	var obm: int = ob.total_notes - ob.hit_notes
	if pbm != obm:
		return pbm < obm
	return pb.pauses < ob.pauses

# -> 1 written, 0 nothing to do, -1 couldn't
func _sync(old_path: String, own_path: String, keep: String) -> int:
	var f := File.new()
	var had_old := f.file_exists(old_path)
	var old := _read(old_path)
	var own := _read(own_path)
	if own.empty() and f.file_exists(own_path + ".bak"):
		own = _read(own_path + ".bak")
	if old.empty() and own.empty():
		return 0 # (nothing readable: left as it is)
	var rows := {}
	if not old.empty():
		rows = old.rows.duplicate()
	# (an old-folder file older clients can't read, or none yet: always written)
	var changed: bool = (not had_old) or old.empty() or int(old.version) > 3
	if not own.empty():
		for key in own.rows.keys():
			var pb: Dictionary = own.rows[key]
			if not rows.has(key) or _better(rows[key], pb):
				rows[key] = pb
				changed = true
	if not changed or rows.empty():
		return 0

	var d := Directory.new()
	if had_old and not d.file_exists(keep):
		d.make_dir_recursive(keep.get_base_dir())
		if d.copy(old_path, keep) != OK:
			return -1 # (only with the original kept)
	if f.open(old_path + ".tmp", File.WRITE) != OK:
		return -1
	f.store_buffer(PoolByteArray(SIG))
	f.store_16(3)
	f.store_64(rows.size())
	for key in rows.keys():
		var pb: Dictionary = rows[key]
		f.store_line(key)
		f.store_8(int(pb.has_passed))
		f.store_16(pb.pauses)
		f.store_32(pb.hit_notes)
		f.store_32(pb.total_notes)
		f.store_32(pb.position)
		f.store_32(pb.length)
		f.store_16(pb.max_combo)
	f.close()
	if had_old:
		d.remove(old_path)
	if d.rename(old_path + ".tmp", old_path) != OK:
		if had_old:
			d.copy(keep, old_path) # (put it back as it was)
		d.remove(old_path + ".tmp")
		return -1
	return 1
