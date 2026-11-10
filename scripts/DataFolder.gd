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
const LINKED := ["maps", "vmaps", "packs", "replays", "content_downloads", "helper"]
const SKIP := ["logs", "cache", "caches", "shader_cache", "vulkan", "render", "tools", "spectate_cache", "pack_update"]
# (the old copies of bests and history the game left for Nightly: chromia/ has them)
const SKIP_WHEN_CHROMIA := ["bests", "score_history"]
const NOTICE_META := "data_folder_moved" # for the menu's one-time notice (Sidebar.gd)

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
	var ui = load("res://scripts/DataFolder.gd").new()
	ui._show(_count(old_dir, true, d.dir_exists(old_dir.plus_file("chromia"))))
	ui._copy_files(old_dir, new_dir, true, d.dir_exists(old_dir.plus_file("chromia")))
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
			ui._copy_files(target, link, false, false)
			notes.append("%s: copied" % name)
	ui._hide()
	_mark(new_dir, old_dir, PoolStringArray(notes).join(", "))
	Engine.set_meta(NOTICE_META, true)
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

static func _skipped(name: String, top: bool, has_chromia: bool) -> bool:
	return top and (name in LINKED or name in SKIP or (has_chromia and name in SKIP_WHEN_CHROMIA))

# how many files a copy will take
static func _count(from: String, top: bool, has_chromia: bool) -> int:
	var d := Directory.new()
	if d.open(from) != OK:
		return 0
	var n := 0
	d.list_dir_begin(true, false)
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not _skipped(name, top, has_chromia):
				n += _count(from.plus_file(name), false, false)
		else:
			n += 1
		name = d.get_next()
	d.list_dir_end()
	return n

# everything in `from` into `to` (the top level skips the big and throwaway folders)
var _done := 0
var _total := 0
func _copy_files(from: String, to: String, top: bool, has_chromia: bool):
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
			if not _skipped(name, top, has_chromia):
				_copy_files(src, dst, false, false)
		else:
			if not File.new().file_exists(dst):
				d.copy(src, dst)
			_done += 1
			if _done % 40 == 0:
				_update()
		name = d.get_next()
	d.list_dir_end()

# ── what's shown meanwhile (the game's own screens aren't loaded yet: a
# plain screen drawn here, and the window's title) ──
var _layer: CanvasLayer = null
var _label: Label = null
var _old_title := ""

func _show(total: int):
	_total = total
	_old_title = String(ProjectSettings.get_setting("application/config/name"))
	OS.set_window_title("Chromia - setting up its own data folder (only this once)")
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree) or tree.root == null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 128
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	_layer.add_child(bg)
	_label = Label.new()
	_label.anchor_right = 1
	_label.anchor_bottom = 1
	_label.align = Label.ALIGN_CENTER
	_label.valign = Label.VALIGN_CENTER
	_label.autowrap = true
	var font := DynamicFont.new()
	font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	font.size = 22
	_label.add_font_override("font", font)
	_label.add_color_override("font_color", Color(0.85, 0.86, 0.9))
	bg.add_child(_label)
	tree.root.add_child(_layer)
	_update()

func _update():
	if _label == null:
		return
	_label.text = "Chromia now has its own data folder.\nCopying your settings, bests and history into it (only this once)...\nYour maps and replays stay where they are.\n\n%d / %d files" % [min(_done, _total), _total]
	VisualServer.force_draw(true, 0.0)

func _hide():
	OS.set_window_title(_old_title)
	if _layer != null and is_instance_valid(_layer):
		_layer.get_parent().remove_child(_layer)
		_layer.free()
	_layer = null
	_label = null
