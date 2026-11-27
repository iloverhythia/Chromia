extends MenuButton

const PROFILES_DIR := "user://profiles"
const COLORSET_DIR := "user://colorsets"
const MESH_DIR := "user://meshes"
const _SETTINGS_PATH := "user://settings.cfg"
const _PICKED_TMP_DIR := "user://_picked_content"

var profiles
var file: File

var overwrite_submenu = PopupMenu.new()
var delete_submenu = PopupMenu.new()


func import_profile():
	Globals.file_sel.open_file(
		self,
		"_on_content_files_selected",
		PoolStringArray(["*.json, *.txt, *.obj, *.mtl, *.glb ; (profile, colorset, mesh)"]),
		false,
		"user://"
	)

func _clear_dir(path: String):
	var dir := Directory.new()
	if dir.open(path) != OK:
		return
	dir.list_dir_begin(true, true)
	var f = dir.get_next()
	while f != "":
		dir.remove(path.plus_file(f))
		f = dir.get_next()
	dir.list_dir_end()

func _on_content_files_selected(files: PoolStringArray):
	if files.empty():
		return

	var obj_files := {}
	var mtl_files := {}
	var handled := {}

	for path in files:
		var ext = path.get_extension().to_lower()
		if ext == "obj" or ext == "glb": # (.glb: a mesh on its own, GlbParse.gd)
			obj_files[path.get_file().get_basename()] = path
		elif ext == "mtl":
			mtl_files[path.get_file().get_basename()] = path

	for base in obj_files.keys():
		if mtl_files.has(base) and obj_files[base].get_extension().to_lower() == "obj":
			_import_mesh_pair(obj_files[base], mtl_files[base], base)
			handled[obj_files[base]] = true
			handled[mtl_files[base]] = true
	for base in obj_files.keys():
		if not handled.has(obj_files[base]):
			_import_mesh_pair(obj_files[base], "", base)
			handled[obj_files[base]] = true
	for base in mtl_files.keys():
		if not handled.has(mtl_files[base]):
			Globals.notify(Globals.NOTIFY_ERROR,
				"'%s.mtl' needs its matching '%s.obj' selected at the same time!!!" % [base, base],
				"Mesh Import Failed")

	for path in files:
		if handled.has(path):
			continue
		var ext = path.get_extension().to_lower()
		match ext:
			"json":
				_import_profile_file(path)
			"txt":
				_import_colorset_file(path)
			"obj", "mtl", "glb":
				pass
			_:
				Globals.notify(Globals.NOTIFY_ERROR,
					"'%s' isn't a supported content file. Use .json (profile), .txt (colorset), or .obj+.mtl or .glb (mesh)." % path.get_file(),
					"Import Failed")

func _import_profile_file(path: String):
	var source_file := File.new()
	if source_file.open(path, File.READ) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not read that settings profile.", "Import Failed")
		return
	var profile_text := source_file.get_as_text()
	source_file.close()
	var parsed = JSON.parse(profile_text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		Globals.notify(Globals.NOTIFY_ERROR, "That file is Not a valid settings profile dummy.", "Import Failed")
		return
	if not parsed.result.has("approach_rate") or not parsed.result.has("sensitivity"):
		Globals.notify(Globals.NOTIFY_ERROR, "That JSON file does not contain Chromia settings you messed up lil bro.", "Import Failed")
		return
	# (shared settings bring their colorset, note mesh and cursor along: ContentBrowser.add_shared_files)
	var shared = parsed.result.get("shared_files")
	var cursor_pic := {}
	var brought := []
	if shared is Dictionary:
		var data: Dictionary = parsed.result
		data.erase("shared_files")
		if shared.get("colorset") is Dictionary:
			var cid := _install_shared_colorset(shared.colorset)
			if cid != "":
				data["selected_colorset"] = cid
				brought.append("colorset")
		if shared.get("mesh") is Dictionary:
			var mid := _install_shared_mesh(shared.mesh)
			if mid != "":
				data["selected_mesh"] = mid
				brought.append("note mesh")
		if shared.get("cursor") is Dictionary and String(shared.cursor.get("ext", "")) in ["png", "jpg", "jpeg", "webp"]:
			cursor_pic = shared.cursor
			brought.append("cursor")
		profile_text = to_json(data)

	var profile_name := path.get_file().get_basename()
	if profile_name.ends_with(".settings"):
		profile_name = profile_name.trim_suffix(".settings")
	if not profile_name.is_valid_filename():
		profile_name = "Imported Profile"
	var destination := Globals.p(PROFILES_DIR.plus_file(profile_name + ".settings.json"))
	var suffix := 2
	while File.new().file_exists(destination):
		destination = Globals.p(PROFILES_DIR.plus_file("%s (%d).settings.json" % [profile_name, suffix]))
		suffix += 1
	var output_file := File.new()
	if output_file.open(destination, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not save the imported profile.", "Import Failed")
		return
	output_file.store_string(profile_text)
	output_file.close()
	# (its cursor beside it: put on when the profile is picked, _use_profile_cursor)
	if not cursor_pic.empty():
		var cb := Marshalls.base64_to_raw(String(cursor_pic.get("data", "")))
		var cf := File.new()
		if cb.size() > 0 and cf.open(destination.trim_suffix(".settings.json") + ".cursor." + String(cursor_pic.ext), File.WRITE) == OK:
			cf.store_buffer(cb)
			cf.close()
	# added as a new profile next to yours (your settings stay as they are)
	_ready()
	var with_files := ""
	if not brought.empty():
		var last: String = brought.pop_back()
		with_files = " with its " + (PoolStringArray(brought).join(", ") + " and " if not brought.empty() else "") + last
	Globals.notify(Globals.NOTIFY_SUCCEED, "Added the profile '%s'%s. Pick it in Presets to use it." % [destination.get_file().trim_suffix(".settings.json"), with_files], "Content Imported")

# a shared colorset: in your colorsets (the same one again is used, not copied) -> its id or ""
func _install_shared_colorset(c: Dictionary) -> String:
	var text := String(c.get("text", ""))
	if text.strip_edges() == "":
		return ""
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(COLORSET_DIR))
	var base := String(c.get("name", "Shared colorset")).strip_edges()
	if not base.is_valid_filename() or base == "":
		base = "Shared colorset"
	var dest := Globals.p(COLORSET_DIR.plus_file(base + ".txt"))
	var n := 2
	while File.new().file_exists(dest):
		var ef := File.new()
		if ef.open(dest, File.READ) == OK:
			var same: bool = ef.get_as_text().strip_edges() == text.strip_edges()
			ef.close()
			if same:
				break
		dest = Globals.p(COLORSET_DIR.plus_file("%s (%d).txt" % [base, n]))
		n += 1
	if not File.new().file_exists(dest):
		var f := File.new()
		if f.open(dest, File.WRITE) != OK:
			return ""
		f.store_string(text)
		f.close()
	var id: String = "custom_" + dest.get_file().to_lower().md5_text()
	Rhythia.load_color_txt(dest, id)
	return id

# a shared note mesh (.obj with its .mtl, or .glb): in your meshes (the same file again is used) -> its id or ""
func _install_shared_mesh(m: Dictionary) -> String:
	var bytes := Marshalls.base64_to_raw(String(m.get("data", "")))
	var fname := String(m.get("file", "")).get_file()
	var ext := fname.get_extension().to_lower()
	if bytes.size() == 0 or not (ext in ["obj", "glb"]):
		return ""
	var base := fname.get_basename()
	if not base.is_valid_filename() or base == "":
		base = "Shared mesh"
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(MESH_DIR))
	var dest := Globals.p(MESH_DIR.plus_file(base + "." + ext))
	var n := 2
	while File.new().file_exists(dest):
		var ef := File.new()
		if ef.open(dest, File.READ) == OK:
			var same: bool = ef.get_buffer(ef.get_len()) == bytes
			ef.close()
			if same:
				break
		dest = Globals.p(MESH_DIR.plus_file("%s (%d).%s" % [base, n, ext]))
		n += 1
	if not File.new().file_exists(dest):
		var f := File.new()
		if f.open(dest, File.WRITE) != OK:
			return ""
		f.store_buffer(bytes)
		f.close()
		var mtl := Marshalls.base64_to_raw(String(m.get("mtl", "")))
		if mtl.size() > 0 and f.open(dest.get_basename() + ".mtl", File.WRITE) == OK:
			f.store_buffer(mtl)
			f.close()
	if ext == "obj":
		var test = load("res://scripts/content/resources/ObjParse.gd").load_obj(dest)
		if test == null or test.get_surface_count() == 0:
			return ""
	var id: String = "ugc_" + dest.get_file().to_lower().replace(" ", "_")
	if Rhythia.registry_mesh != null and not (Rhythia.registry_mesh.get_item(id) is NoteMesh):
		Rhythia.registry_mesh.add_item(NoteMesh.new(id, dest.get_file().get_basename() + " (custom)", dest, "You"))
	return id

# a profile that came with a cursor: that cursor on when it's picked
static func _use_profile_cursor(profile_path: String):
	var stem := profile_path.trim_suffix(".settings.json")
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var side: String = stem + ".cursor." + String(ext)
		if File.new().file_exists(side):
			for old in ["png", "jpg", "jpeg", "webp", "bmp", "gif"]:
				var op: String = Globals.p("user://cursor." + old)
				if File.new().file_exists(op):
					Directory.new().remove(op)
			Directory.new().copy(side, Globals.p("user://cursor." + ext))
			return


func _import_colorset_file(path: String):
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(COLORSET_DIR)):
		dir.make_dir_recursive(Globals.p(COLORSET_DIR))

	var source_file := File.new()
	if source_file.open(path, File.READ) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not read that colorset file.", "Import Failed")
		return
	var content := source_file.get_as_text()
	source_file.close()

	var name := path.get_file()
	var destination := Globals.p(COLORSET_DIR.plus_file(name))
	var n := 2
	while File.new().file_exists(destination):
		name = "%s (%d).%s" % [path.get_file().get_basename(), n, path.get_extension()]
		destination = Globals.p(COLORSET_DIR.plus_file(name))
		n += 1
	var output_file := File.new()
	if output_file.open(destination, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not save the colorset.", "Import Failed")
		return
	output_file.store_string(content)
	output_file.close()
	Rhythia.load_color_txt(destination, "custom_" + destination.get_file().to_lower().md5_text()) # (in the list right away)
	Globals.notify(Globals.NOTIFY_SUCCEED, "Imported colorset '%s'." % name, "Content Imported")

func _import_mesh_pair(obj_path: String, mtl_path: String, base_name: String):
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(MESH_DIR)):
		dir.make_dir_recursive(Globals.p(MESH_DIR))

	# (lowercase .obj / .glb: the game only loads those from the meshes folder)
	var mext: String = "glb" if obj_path.get_extension().to_lower() == "glb" else "obj"
	var obj_dest := Globals.p(MESH_DIR.plus_file(obj_path.get_file().get_basename() + "." + mext))
	if dir.copy(obj_path, obj_dest) != OK or (mtl_path != "" and dir.copy(mtl_path, obj_dest.get_basename() + ".mtl") != OK):
		Globals.notify(Globals.NOTIFY_ERROR, "Could not save mesh '%s'." % base_name, "Import Failed")
		return
	var test = load("res://scripts/content/resources/ObjParse.gd").load_obj(obj_dest)
	if test == null or test.get_surface_count() == 0:
		dir.remove(obj_dest)
		Globals.notify(Globals.NOTIFY_ERROR, "'%s' isn't a mesh the game can read." % obj_path.get_file(), "Import Failed")
		return
	var id: String = "ugc_" + obj_dest.get_file().to_lower().replace(" ", "_")
	if Rhythia.registry_mesh != null and not (Rhythia.registry_mesh.get_item(id) is NoteMesh):
		Rhythia.registry_mesh.add_item(NoteMesh.new(id, base_name + " (custom)", obj_dest, "You"))
	Globals.notify(Globals.NOTIFY_SUCCEED, "Imported mesh '%s'. Pick it in Settings > Meshes." % base_name, "Content Imported")

func export_profile():
	var profile_path := _get_active_profile_path()
	if profile_path == "" or not File.new().file_exists(profile_path):
		profile_path = Globals.p("user://settings.json")
		Rhythia.save_settings(profile_path)
	else:
		Rhythia.save_settings(profile_path)
	var profile_file := File.new()
	if profile_file.open(profile_path, File.READ) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not read the active profile.", "Export Failed")
		return
	var profile_bytes := profile_file.get_buffer(profile_file.get_len())
	profile_file.close()
	Globals.file_sel.save_file(self, "_save_exported_profile", PoolStringArray(["*.json ; Chromia settings profile"]), "user://")
	_export_profile_bytes = profile_bytes

var _export_profile_bytes := PoolByteArray()

func _save_exported_profile(path: String):
	if path == "":
		return
	var output_file := File.new()
	if output_file.open(path, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not write the exported profile.", "Export Failed")
		return
	output_file.store_buffer(_export_profile_bytes)
	output_file.close()

func save_profile(path: String):
	if path:
		var saveLoc: File = File.new()
		var err: int = saveLoc.open(path, File.WRITE)
		if err != OK: print("file.open errored - code " + String(err))
		saveLoc.store_string(file.get_as_text())
		saveLoc.close()
		file.close()

		_ready()

func _get_active_profile_path() -> String:
	return Rhythia.get_active_profile_path()

func _set_active_profile_path(path: String):
	Rhythia.set_active_profile_path(path)

func on_pressed(i):
	if i == profiles.size() + 1:
		var title = "Enter Profile Name"
		var valid = false
		var response: int = 0
		while not valid and response != 1:
			Globals.string_prompt.open(
				"Input a valid file name for the new profile",
				title,
				"Profile Name",
				[
					{text = "OK"},
					{text = "Cancel", wait = 0}
				]
			)
			title = "Invalid Profile Name"
			Globals.string_prompt.s_alert.play()
			response = yield(Globals.string_prompt, "option_selected")
			Globals.string_prompt.close()
			if response == 0:
				yield(get_tree().create_timer(0.6), "timeout")
				valid = Globals.string_prompt.input.get_text().is_valid_filename()

		if response == 0:
			Rhythia.save_settings()
			var new_path = Globals.p(PROFILES_DIR.plus_file(Globals.string_prompt.input.get_text() + ".settings.json"))
			Rhythia.save_settings(new_path)
			_set_active_profile_path(new_path)
			# (Settings > Transfer > Settings backups: a new profile is always copied there)
			if Rhythia.settings_backup:
				Rhythia.settings_backup_now("profile " + new_path.get_file().trim_suffix(".settings.json"), new_path)
		_ready()
		return
	if i == profiles.size() + 2:
		import_profile()
		return
	if i == profiles.size() + 3:
		export_profile()
		return

	var profile = profiles[i]
	print("Loading profile: " + profile)
	Rhythia.trail("profile switch: " + profile.get_file())
	_use_profile_cursor(profile)
	_set_active_profile_path(profile)
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/init.tscn")
	Rhythia.load_saved_settings(profile)
	Rhythia.save_settings()

func _migrate_legacy_profiles():
	var dir := Directory.new()
	dir.open(Globals.p("user://"))
	var legacy = Globals.get_files_recursive([Globals.p("user://")], 1, "json").files
	for path in legacy:
		if path.find(".settings.json") == -1:
			continue

		var dest = path.get_base_dir().plus_file("profiles").plus_file(path.get_file())
		if dir.file_exists(dest):
			continue
		var err = dir.rename(path, dest)
		if err != OK:
			print("Failed to migrate profile '%s' to profiles folder - err %s" % [path, err])
		else:
			print("Migrated profile to profiles folder: " + path)

# Files dragged onto the window (RunMapButton.gd): profiles, colorsets and
# meshes go in like Import Content
static func import_dropped(tree: SceneTree, files: PoolStringArray) -> bool:
	for n in tree.get_nodes_in_group("settings_profiles"):
		n._on_content_files_selected(files)
		return true
	return false

func _ready():
	if not is_in_group("settings_profiles"):
		add_to_group("settings_profiles")
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(PROFILES_DIR)):
		dir.make_dir_recursive(Globals.p(PROFILES_DIR))
	_migrate_legacy_profiles()

	get_popup().clear()
	delete_submenu.clear()
	overwrite_submenu.clear()
	profiles = Globals.get_files_recursive([Globals.p(PROFILES_DIR)], 1, "json").files
	for i in range(profiles.size() - 1, -1, -1):
		if profiles[i].find(".settings.json") == -1:
			profiles.remove(i)

	var active_path = _get_active_profile_path()
	for i in range(profiles.size()):
		var profileName = profiles[i].substr(profiles[i].find_last("/") + 1, profiles[i].find(".settings.json") - profiles[i].find_last("/") - 1)
		get_popup().add_item(profileName, i)
		delete_submenu.add_item(profileName, i)
		overwrite_submenu.add_item(profileName, i)
		if active_path != "" and profiles[i].replace("\\", "/").get_file() == active_path.get_file():
			get_popup().set_item_as_checkable(i, true)
			get_popup().set_item_checked(i, true)

	get_popup().add_separator()
	get_popup().add_item("Create New From Current", profiles.size() + 1)
	get_popup().add_item("Import Content...", profiles.size() + 2)
	get_popup().add_item("Export Active Profile...", profiles.size() + 3)
	var import_button = get_parent().get_node_or_null("ImportProfile")
	if import_button and not import_button.is_connected("pressed", self, "import_profile"):
		import_button.connect("pressed", self, "import_profile")

	overwrite_submenu.name = "Overwrite"
	delete_submenu.name = "Delete"

	# _ready runs again whenever the list changes; only wire things up once.
	if overwrite_submenu.get_parent() == null:
		get_popup().call_deferred("add_child", overwrite_submenu)
		get_popup().call_deferred("add_child", delete_submenu)
		overwrite_submenu.connect("id_pressed", self, "overwrite_profile")
		delete_submenu.connect("id_pressed", self, "delete_profile")
		get_popup().connect("id_pressed", self, "on_pressed")
		# (the button opens the panel below instead of this little menu)
		get_popup().connect("about_to_show", self, "_menu_to_panel")
	if _panel != null and is_instance_valid(_panel) and _panel.visible:
		_fill_panel()

	get_popup().add_submenu_item("Overwrite Profile", "Overwrite", -1)
	get_popup().add_submenu_item("Delete Profile", "Delete", -1)

func overwrite_profile(i):
	var profile = profiles[i]
	print("Overwriting profile: " + profile)
	Rhythia.save_settings(profile)
	_set_active_profile_path(profile)
	_ready()

func delete_profile(i):
	var profile = profiles[i]
	print("Deleting profile: " + profile)
	var userDir = Directory.new()
	userDir.open(Globals.p(PROFILES_DIR))
	var res: int = userDir.remove(profile)
	if res != OK:
		Globals.confirm_prompt.open(
			"An error occurred while deleting your settings file. " +
			"Try manually deleting it, if that doesn't work, " +
			"POLITELY ASK for help in the Discord server.\n" +
			"discord.gg/NmAswT2rEY" +
			"\n(error code %s)" % res,
			"Error",
			[{text = "OK"}]
		)

	_ready()

# --- the profiles panel ---------------------------------------------------------
# "Select Profile" used to open a small menu that ran off the screen with many
# profiles (no way to scroll it) and hid Overwrite and Delete in side menus.
# It opens a panel beside the button instead: every profile in a list that
# scrolls, each with Save over and Delete next to it, New / Import / Export
# under the list, and an X in its corner. It stays open until you close it
# (the X, Esc, or the button again).

const PANEL_W := 440.0
const PANEL_H := 560.0
var _panel: PanelContainer = null
var _rows: VBoxContainer = null

func _menu_to_panel():
	get_popup().call_deferred("hide")
	call_deferred("_toggle_panel")

func _toggle_panel():
	if _panel != null and is_instance_valid(_panel) and _panel.visible:
		_close_panel()
	else:
		_open_panel()

func _close_panel():
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = false

# the page the panel sits on (so it goes with it), else the menu
func _panel_host() -> Control:
	var n: Node = self
	while n != null:
		if n is Control and n.name == "Settings":
			return n as Control
		n = n.get_parent()
	var vp := get_viewport()
	var m = vp.get_node_or_null("Menu") if vp != null else null
	return m if m is Control else (get_parent() as Control)

func _pbtn(text: String, parent: Node, method: String, binds: Array = [], width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme if theme != null else load("res://uitheme.tres")
	b.rect_min_size = Vector2(width, 34)
	b.focus_mode = FOCUS_NONE
	b.clip_text = width > 0.0
	b.connect("pressed", self, method, binds)
	parent.add_child(b)
	return b

func _open_panel():
	var MS = load("res://scripts/ui/menu/MenuStyle.gd")
	if _panel == null or not is_instance_valid(_panel):
		_panel = PanelContainer.new()
		_panel.name = "ProfilesPanel"
		_panel.theme = load("res://uitheme.tres")
		var host := _panel_host()
		host.add_child(_panel)
		host.connect("visibility_changed", self, "_close_panel")
		var v := VBoxContainer.new()
		v.add_constant_override("separation", 8)
		_panel.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		var title := Label.new()
		title.text = "Profiles"
		title.size_flags_horizontal = SIZE_EXPAND_FILL
		title.add_font_override("font", get_font("font"))
		head.add_child(title)
		var x := _pbtn("X", head, "_close_panel", [], 38.0)
		x.hint_tooltip = "Close"
		var hint := Label.new()
		hint.text = "Click a profile to switch to it."
		hint.modulate = Color(1, 1, 1, 0.65)
		v.add_child(hint)
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = SIZE_EXPAND_FILL
		sc.scroll_horizontal_enabled = false
		v.add_child(sc)
		_rows = VBoxContainer.new()
		_rows.size_flags_horizontal = SIZE_EXPAND_FILL
		_rows.add_constant_override("separation", 6)
		sc.add_child(_rows)
		v.add_child(HSeparator.new())
		_pbtn("Create New From Current", v, "_panel_action", [1])
		var foot := HBoxContainer.new()
		foot.add_constant_override("separation", 8)
		v.add_child(foot)
		var imp := _pbtn("Import Content...", foot, "_panel_action", [2])
		imp.size_flags_horizontal = SIZE_EXPAND_FILL
		var ex := _pbtn("Export Active Profile...", foot, "_panel_action", [3])
		ex.size_flags_horizontal = SIZE_EXPAND_FILL
	# (in your menu look: Settings > Menu Customizer)
	var sb := StyleBoxFlat.new()
	sb.bg_color = MS.bg_color(Color(0.317647, 0.227451, 0.345098))
	sb.bg_color.a = 1.0
	sb.border_color = MS.bg_color(Color(0.764706, 0.65098, 0.8))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	_panel.add_stylebox_override("panel", sb)
	_fill_panel()
	_panel.visible = true
	_panel.raise()
	_place_panel()

# beside the button: above it when there is room there, else below, inside the page
func _place_panel():
	var host := _panel.get_parent() as Control
	if host == null:
		return
	var area := Rect2(host.rect_global_position, host.rect_size)
	var mine := get_global_rect()
	var h: float = min(PANEL_H, max(260.0, area.size.y - 32.0))
	var w: float = min(PANEL_W, area.size.x - 32.0)
	var above: float = mine.position.y - area.position.y
	var below: float = area.end.y - mine.end.y
	var y: float = mine.position.y - 8.0 - h if above >= below else mine.end.y + 8.0
	y = clamp(y, area.position.y + 16.0, max(area.position.y + 16.0, area.end.y - 16.0 - h))
	var x: float = clamp(mine.position.x, area.position.x + 16.0, max(area.position.x + 16.0, area.end.x - 16.0 - w))
	_panel.rect_min_size = Vector2(w, h)
	_panel.rect_size = Vector2(w, h)
	_panel.rect_global_position = Vector2(x, y)

func _fill_panel():
	if _rows == null or not is_instance_valid(_rows):
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var active := _get_active_profile_path().get_file()
	if profiles.empty():
		var none := Label.new()
		none.text = "No profiles yet. \"Create New From Current\" saves your settings as one."
		none.autowrap = true
		_rows.add_child(none)
	for i in range(profiles.size()):
		var path: String = String(profiles[i]).replace("\\", "/")
		var pname: String = path.get_file().trim_suffix(".settings.json")
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 6)
		_rows.add_child(row)
		var is_active: bool = active != "" and path.get_file() == active
		var b := _pbtn(("> " if is_active else "") + pname, row, "_panel_load", [i])
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.align = Button.ALIGN_LEFT
		b.clip_text = true
		b.hint_tooltip = ("The profile you are on: " if is_active else "Switch to ") + pname
		var o := _pbtn("Save over", row, "_panel_overwrite", [i], 96.0)
		o.hint_tooltip = "Save your current settings over \"%s\"" % pname
		var del := _pbtn("Delete", row, "_panel_delete", [i], 76.0)
		del.hint_tooltip = "Delete \"%s\"" % pname

func _panel_action(which: int):
	on_pressed(profiles.size() + which)

func _panel_load(i: int):
	_close_panel()
	on_pressed(i)

func _ask(body: String, title: String, yes: String) -> bool:
	Globals.confirm_prompt.s_alert.play()
	Globals.confirm_prompt.open(body, title, [{text = "Cancel"}, {text = yes}])
	var picked: int = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.s_back.play()
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	return picked == 1

func _panel_overwrite(i: int):
	if i < 0 or i >= profiles.size():
		return
	var pname: String = String(profiles[i]).get_file().trim_suffix(".settings.json")
	if yield(_ask("Save your current settings over the profile \"%s\"? What it holds now is replaced." % pname, "Save over profile", "Save over it"), "completed"):
		overwrite_profile(i)

func _panel_delete(i: int):
	if i < 0 or i >= profiles.size():
		return
	var pname: String = String(profiles[i]).get_file().trim_suffix(".settings.json")
	if yield(_ask("Delete the profile \"%s\"? This can't be undone." % pname, "Delete profile", "Delete"), "completed"):
		delete_profile(i)

func _unhandled_input(event):
	if _panel != null and is_instance_valid(_panel) and _panel.visible and event.is_action_pressed("ui_cancel"):
		_close_panel()
		get_tree().set_input_as_handled()
