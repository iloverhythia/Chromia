extends Reference

# Chromia's own data folder (computers): %APPDATA%\Chromia on Windows, not
# "SoundSpacePlus", the folder Rhythia Nightly (and Chromia before it) use.
# Two games reading and writing the same settings, bests and colorsets broke
# each other. (The folder's name is the project setting
# application/config/custom_user_dir_name, set to "Chromia" when the game is
# built: .github/workflows/release.yml.)
#
# The first start with the new folder fills it from the old one, before any
# other script runs (PackUpdate.gd calls migrate()):
#   - everything small (settings, profiles, bests, attempt history, skins,
#     colorsets, meshes, sounds, pictures...) is copied; the old folder is
#     left as it was, as a backup;
#   - the big folders (maps, packs, replays...) aren't copied: the new folder
#     gets a link to the old one (a directory junction on Windows), so the
#     game sees them where it always did, nothing is moved, and an old game
#     using the old folder still has them. If a link can't be made, the folder
#     is moved instead (instant on the same drive).
# chromia/moved_from.txt marks it done (with where it came from).

const OLD_NAME := "SoundSpacePlus"
const MARKER := "chromia/moved_from.txt"
const LINKED := ["maps", "vmaps", "packs", "replays", "content_downloads"]
const SKIP := ["logs", "cache", "caches", "shader_cache", "vulkan", "render", "tools", "spectate_cache", "pack_update"]

static func migrate():
	if not (OS.has_feature("Windows") or OS.has_feature("X11") or OS.has_feature("OSX")) or OS.has_feature("editor"):
		return
	var new_dir: String = OS.get_user_data_dir()
	if new_dir.get_file() == OLD_NAME:
		return # (a build still on the old folder)
	var old_dir: String = new_dir.get_base_dir().plus_file(OLD_NAME)
	var d := Directory.new()
	var f := File.new()
	if not d.dir_exists(old_dir) or f.file_exists(new_dir.plus_file(MARKER)):
		return
	# (a folder that's already in use: it isn't filled over)
	if f.file_exists(new_dir.plus_file("settings.json")):
		_mark(new_dir, old_dir, "the new folder already had settings: nothing copied")
		return
	print("[data folder] moving in from %s" % old_dir)
	var t0 := OS.get_ticks_msec()
	d.make_dir_recursive(new_dir)
	var notes := []
	_copy(old_dir, new_dir, true)
	for name in LINKED:
		var target: String = old_dir.plus_file(name)
		var link: String = new_dir.plus_file(name)
		if not d.dir_exists(target) or d.dir_exists(link):
			continue
		if _link(link, target):
			notes.append("%s: linked" % name)
		elif d.rename(target, link) == OK:
			notes.append("%s: moved" % name)
		else:
			_copy(target, link, false)
			notes.append("%s: copied" % name)
	_mark(new_dir, old_dir, PoolStringArray(notes).join(", "))
	print("[data folder] done in %d ms (%s)" % [OS.get_ticks_msec() - t0, PoolStringArray(notes).join(", ")])

static func _mark(new_dir: String, old_dir: String, how: String):
	Directory.new().make_dir_recursive(new_dir.plus_file("chromia"))
	var f := File.new()
	if f.open(new_dir.plus_file(MARKER), File.WRITE) == OK:
		f.store_string("%s\n%s\n%s\n" % [old_dir, OS.get_unix_time(), how])
		f.close()

# a link at `link` to the folder `target` -> true when it's there
static func _link(link: String, target: String) -> bool:
	var out := []
	if OS.has_feature("Windows"):
		# a junction needs no admin rights (a symbolic link does)
		OS.execute("cmd.exe", PoolStringArray(["/c", "mklink", "/J", link.replace("/", "\\"), target.replace("/", "\\")]), true, out)
	else:
		OS.execute("ln", PoolStringArray(["-s", target, link]), true, out)
	return Directory.new().dir_exists(link)

# everything in `from` into `to` (the top level skips the big and throwaway folders)
static func _copy(from: String, to: String, top: bool):
	var d := Directory.new()
	if d.open(from) != OK:
		return
	d.make_dir_recursive(to)
	d.list_dir_begin(true, false)
	var name := d.get_next()
	while name != "":
		var src: String = from.plus_file(name)
		var dst: String = to.plus_file(name)
		if d.current_is_dir():
			if not (top and (name in LINKED or name in SKIP)):
				_copy(src, dst, false)
		elif not File.new().file_exists(dst):
			d.copy(src, dst)
		name = d.get_next()
	d.list_dir_end()
