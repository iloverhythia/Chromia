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

var _web_content_cb

func import_profile():
	if OS.has_feature("HTML5") and OS.has_feature("JavaScript"):
		_open_web_content_picker()
	else:
		Globals.file_sel.open_file(
			self,
			"_on_content_files_selected",
			PoolStringArray(["*.json, *.txt, *.obj, *.mtl ; (profile, colorset, mesh)"]),
			false,
			"user://"
		)

func _open_web_content_picker():
	if _web_content_cb == null:
		_web_content_cb = JavaScript.create_callback(self, "_on_web_content_picked")
	var win = JavaScript.get_interface("window")
	win.saviaContentPickCb = _web_content_cb
	JavaScript.eval( \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
		"\n\t(function () {\n\t\tvar input = document.createElement('input');\n\t\tinput.type = 'file';\n\t\tinput.multiple = true;\n\t\tinput.accept = '.json,.txt,.obj,.mtl,application/json,text/plain';\n\t\tinput.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0;';\n\t\tdocument.body.appendChild(input);\n\t\tinput.addEventListener('change', function () {\n\t\t\tvar files = Array.prototype.slice.call(input.files || []);\n\t\t\tif (!files.length) { input.remove(); return; }\n\t\t\tvar results = [];\n\t\t\tvar remaining = files.length;\n\t\t\tfiles.forEach(function (f) {\n\t\t\t\tvar reader = new FileReader();\n\t\t\t\treader.onload = function () {\n\t\t\t\t\tvar bytes = new Uint8Array(reader.result);\n\t\t\t\t\tvar bin = '';\n\t\t\t\t\tfor (var i = 0; i < bytes.length; i += 0x8000) {\n\t\t\t\t\t\tbin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));\n\t\t\t\t\t}\n\t\t\t\t\tresults.push({ name: f.name, data: btoa(bin) });\n\t\t\t\t\tremaining--;\n\t\t\t\t\tif (remaining === 0) {\n\t\t\t\t\t\twindow.saviaContentPickCb(JSON.stringify(results));\n\t\t\t\t\t\tinput.remove();\n\t\t\t\t\t}\n\t\t\t\t};\n\t\t\t\treader.readAsArrayBuffer(f);\n\t\t\t});\n\t\t});\n\t\tinput.click();\n\t})();\n\t", true)

func _on_web_content_picked(args):
	if args.size() < 1:
		return
	var parsed = JSON.parse(str(args[0]))
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not read the picked files.", "Import Failed")
		return

	var dir := Directory.new()
	if dir.dir_exists(Globals.p(_PICKED_TMP_DIR)):
		_clear_dir(Globals.p(_PICKED_TMP_DIR))
	else:
		dir.make_dir_recursive(Globals.p(_PICKED_TMP_DIR))

	var paths := PoolStringArray()
	for entry in parsed.result:
		var raw = Marshalls.base64_to_raw(String(entry.data))
		var tmp_path = Globals.p(_PICKED_TMP_DIR.plus_file(String(entry.name)))
		var f := File.new()
		if f.open(tmp_path, File.WRITE) != OK:
			continue
		f.store_buffer(raw)
		f.close()
		paths.append(tmp_path)

	_on_content_files_selected(paths)

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
		if ext == "obj":
			obj_files[path.get_file().get_basename()] = path
		elif ext == "mtl":
			mtl_files[path.get_file().get_basename()] = path

	for base in obj_files.keys():
		if mtl_files.has(base):
			_import_mesh_pair(obj_files[base], mtl_files[base], base)
			handled[obj_files[base]] = true
			handled[mtl_files[base]] = true
	for base in obj_files.keys():
		if not handled.has(obj_files[base]):
			Globals.notify(Globals.NOTIFY_ERROR,
				"'%s.obj' needs its matching '%s.mtl' selected at the same time!!!!!" % [base, base],
				"Mesh Import Failed")
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
			"obj", "mtl":
				pass
			_:
				Globals.notify(Globals.NOTIFY_ERROR,
					"'%s' isn't a supported content file. Use .json (profile), .txt (colorset), or .obj+.mtl (mesh)." % path.get_file(),
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
		Globals.notify(Globals.NOTIFY_ERROR, "That JSON file does not contain Savia settings you messed up lil bro.", "Import Failed")
		return

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
	_set_active_profile_path(destination)
	profiles.append(destination)
	on_pressed(profiles.size() - 1)


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
	var output_file := File.new()
	if output_file.open(destination, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not save the colorset.", "Import Failed")
		return
	output_file.store_string(content)
	output_file.close()
	Globals.notify(Globals.NOTIFY_SUCCESS, "Imported colorset '%s'." % name, "Content Imported")

func _import_mesh_pair(obj_path: String, mtl_path: String, base_name: String):
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(MESH_DIR)):
		dir.make_dir_recursive(Globals.p(MESH_DIR))

	var obj_dest := Globals.p(MESH_DIR.plus_file(obj_path.get_file()))
	var mtl_dest := Globals.p(MESH_DIR.plus_file(mtl_path.get_file()))

	if dir.copy(obj_path, obj_dest) != OK or dir.copy(mtl_path, mtl_dest) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not save mesh '%s'." % base_name, "Import Failed")
		return
	Globals.notify(Globals.NOTIFY_SUCCESS, "Imported mesh '%s'." % base_name, "Content Imported")

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
	var filename := profile_path.get_file()
	if OS.has_feature("HTML5") and OS.has_feature("JavaScript"):
		JavaScript.download_buffer(profile_bytes, filename, "application/json")
	else:
		Globals.file_sel.save_file(self, "_save_exported_profile", PoolStringArray(["*.json ; Savia settings profile"]), "user://")
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
	var config = ConfigFile.new()
	if config.load(_SETTINGS_PATH) != OK:
		return ""
	return String(config.get_value("profile", "active_profile_path", ""))

func _set_active_profile_path(path: String):
	var config = ConfigFile.new()
	config.load(_SETTINGS_PATH)
	config.set_value("profile", "active_profile_path", path)
	config.save(_SETTINGS_PATH)

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

func _ready():
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
		if profiles[i] == active_path:
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

	get_popup().call_deferred("add_child", overwrite_submenu)
	get_popup().call_deferred("add_child", delete_submenu)

	overwrite_submenu.connect("id_pressed", self, "overwrite_profile")
	delete_submenu.connect("id_pressed", self, "delete_profile")

	get_popup().add_submenu_item("Overwrite Profile", "Overwrite", -1)
	get_popup().add_submenu_item("Delete Profile", "Delete", -1)
	get_popup().connect("id_pressed", self, "on_pressed")

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
