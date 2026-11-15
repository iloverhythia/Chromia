extends Node

# Bests that Chromia saved in the old shared "SoundSpacePlus" folder (before it
# had its own: DataFolder.gd) are in Chromia's newer file format (version 4,
# with a date on each best). Rhythia Nightly and other older clients only read
# up to version 3, so to them those files looked broken: their bests didn't
# show, and the next pass was saved over them.
#
# Chromia reads its bests from its own folder now (user://chromia/bests), so
# once, on a computer with its own Chromia folder, every version 4 file in
# SoundSpacePlus\bests is written again as version 3: the same bests without
# the dates. The file as it was is kept in user://chromia/old_folder_bests.
# Files that are already version 3 or older (or can't be read) are left alone.

const OLD_NAME := "SoundSpacePlus"
const MARKER := "user://chromia/old_folder_bests_fixed.txt"
const KEEP_DIR := "user://chromia/old_folder_bests"
const SIG := [83, 83, 43, 112, 66] # "SS+pB"

var _thread: Thread = null
var _old_bests := ""

# (Savia.gd, at startup)
static func start(parent: Node):
	if not (OS.has_feature("Windows") or OS.has_feature("X11") or OS.has_feature("OSX")) or OS.has_feature("editor"):
		return
	var own: String = OS.get_user_data_dir()
	if own.get_file() == OLD_NAME:
		return # (a build still on the shared folder: its bests are in chromia/bests, untouched)
	var old_bests: String = own.get_base_dir().plus_file(OLD_NAME).plus_file("bests")
	if File.new().file_exists(Globals.p(MARKER)) or not Directory.new().dir_exists(old_bests):
		return
	var n = load("res://scripts/OldFolderBests.gd").new()
	n.name = "OldFolderBests"
	n._old_bests = old_bests
	parent.call_deferred("add_child", n) # (the game is still starting up)

func _ready():
	var old_bests := _old_bests
	if OS.can_use_threads():
		_thread = Thread.new()
		if _thread.start(self, "_job", old_bests) == OK:
			return
		_thread = null
	_done(_job(old_bests))

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

func _job(old_bests: String) -> String:
	var d := Directory.new()
	if d.open(old_bests) != OK:
		return "couldn't open %s" % old_bests
	var keep: String = Globals.p(KEEP_DIR)
	var fixed := 0
	var failed := 0
	d.list_dir_begin(true, true)
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.get_extension() == "":
			var r := _fix(old_bests.plus_file(fn), keep.plus_file(fn))
			if r == 1: fixed += 1
			elif r == -1: failed += 1
		fn = d.get_next()
	d.list_dir_end()
	return "%d files made readable for older clients, %d couldn't be" % [fixed, failed]

# -> 1 rewritten, 0 nothing to do, -1 couldn't
func _fix(path: String, keep: String) -> int:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return -1
	if f.get_len() < 15 or f.get_buffer(5) != PoolByteArray(SIG):
		f.close()
		return 0
	if f.get_16() != 4:
		f.close()
		return 0
	var amt: int = f.get_64()
	var rows := []
	for i in range(amt):
		if f.eof_reached():
			f.close()
			return 0 # (damaged: left as it is)
		var row := {}
		row.key = f.get_line()
		row.passed = f.get_8()
		row.pauses = f.get_16()
		row.hit = f.get_32()
		row.total = f.get_32()
		row.pos = f.get_32()
		row.length = f.get_32()
		row.combo = f.get_16()
		f.get_64() # (the date: version 3 has none)
		rows.append(row)
	f.close()

	var d := Directory.new()
	d.make_dir_recursive(keep.get_base_dir())
	if not d.file_exists(keep) and d.copy(path, keep) != OK:
		return -1 # (only with the original kept)
	if f.open(path + ".tmp", File.WRITE) != OK:
		return -1
	f.store_buffer(PoolByteArray(SIG))
	f.store_16(3)
	f.store_64(rows.size())
	for row in rows:
		f.store_line(row.key)
		f.store_8(row.passed)
		f.store_16(row.pauses)
		f.store_32(row.hit)
		f.store_32(row.total)
		f.store_32(row.pos)
		f.store_32(row.length)
		f.store_16(row.combo)
	f.close()
	d.remove(path)
	if d.rename(path + ".tmp", path) != OK:
		d.copy(keep, path) # (put it back as it was)
		d.remove(path + ".tmp")
		return -1
	return 1
