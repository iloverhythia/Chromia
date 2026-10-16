extends Node
class_name RhsImporter

signal import_finished(result)

const IMAGE_EXTS = ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
const SOUND_EXTS = ["ogg", "mp3", "wav"]

const TMP_ZIP := "user://tmp_rhs_import.zip"
const TMP_DIR := "user://tmp_rhs_import"

func _real_path(user_path: String) -> String:
	return user_path.replace("user://", OS.get_user_data_dir() + "/")

func _extract_zip(zip_path: String, dest_dir: String, exec_log: Dictionary) -> bool:
	var dir := Directory.new()
	dir.make_dir_recursive(dest_dir)
	var output := []
	var exit_code := OS.execute("tar.exe", ["-xf", zip_path, "-C", dest_dir], true, output, true)
	exec_log.exit_code = exit_code
	exec_log.output = PoolStringArray(output).join(" ")
	return exit_code == 0

func _remove_dir_recursive(path: String):
	var dir := Directory.new()
	if dir.open(path) != OK:
		return
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	while f != "":
		var full := path.plus_file(f)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			dir.remove(full)
		f = dir.get_next()
	dir.list_dir_end()
	dir.remove(path)

func _cleanup():
	var dir := Directory.new()
	dir.remove(Globals.p(TMP_ZIP))
	_remove_dir_recursive(Globals.p(TMP_DIR))

func _slugify(s: String) -> String:
	var out := ""
	var lower = s.to_lower()
	for i in range(lower.length()):
		var c = lower[i]
		if "0123456789abcdefghijklmnopqrstuvwxyz".find(c) != -1:
			out += c
		elif out != "" and out[out.length() - 1] != "_":
			out += "_"
	return out.trim_suffix("_")

func _find_file(root: String, category: String, exts: Array) -> String:
	var dir := Directory.new()
	var folder := root.plus_file(category)
	if dir.open(folder) != OK:
		return ""
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	var found := ""
	while f != "":
		if not dir.current_is_dir() and exts.has(f.get_extension().to_lower()):
			found = folder.plus_file(f)
			break
		f = dir.get_next()
	dir.list_dir_end()
	return found

func _copy_file(src: String, dest: String) -> bool:
	var dir := Directory.new()
	return dir.copy(src, Globals.p(dest)) == OK

func _find_first_image_recursive(folder: String) -> String:
	var dir := Directory.new()
	if dir.open(folder) != OK:
		return ""
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	var subdirs := []
	var found := ""
	while f != "":
		var full := folder.plus_file(f)
		if dir.current_is_dir():
			subdirs.append(full)
		elif IMAGE_EXTS.has(f.get_extension().to_lower()):
			found = full
			break
		f = dir.get_next()
	dir.list_dir_end()
	if found != "":
		return found
	subdirs.sort()
	for sub in subdirs:
		found = _find_first_image_recursive(sub)
		if found != "":
			return found
	return ""

const SETTINGS_ROOT := "Menu/Main/Settings/S/F/TabContainer"

func _sync_range_control(ui_path: String, value):
	if ui_path == "":
		return
	var node = get_tree().get_root().get_node_or_null(ui_path)
	if node != null and node is Range:
		node.value = value

func _apply_value(cfg: Dictionary, key: String, rhythia_var: String, result: Dictionary, label: String, ui_path: String = "", ui_scale: float = 1.0):
	if cfg.has(key) and typeof(cfg[key]) == TYPE_DICTIONARY and cfg[key].has("Value"):
		var v = cfg[key].Value
		Rhythia.set(rhythia_var, v)
		_sync_range_control(ui_path, float(v) * ui_scale)
		result.imported.append(label)

func import_rhs(path: String) -> Dictionary:
	yield(get_tree(), "idle_frame")

	var result := {"imported": [], "skipped": [], "errors": []}
	var dir := Directory.new()

	if dir.copy(path, Globals.p(TMP_ZIP)) != OK:
		result.errors.append("Couldn't read the selected file.")
		return result

	var exec_log := {"exit_code": -1, "output": ""}
	if not _extract_zip(_real_path(TMP_ZIP), _real_path(TMP_DIR), exec_log):
		result.errors.append("Couldn't extract the archive (tar exit %s: %s)" % [exec_log.exit_code, exec_log.output])
		_cleanup()
		return result

	var root := Globals.p(TMP_DIR)

	var config_file := File.new()
	if config_file.open(root.plus_file("config"), File.READ) != OK:
		result.errors.append("No 'config' found inside — is this really a .rhs file?")
		_cleanup()
		return result
	var config_text := config_file.get_as_text()
	config_file.close()

	var parsed = JSON.parse(config_text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		result.errors.append("config inside the archive isn't valid JSON.")
		_cleanup()
		return result
	var cfg: Dictionary = parsed.result

	var note_path := _find_file(root, "noteSkin", ["obj"])
	if note_path != "":
		var mesh_name := ""
		var rnote_path := _find_file(root, "noteSkin", ["json"])
		if rnote_path != "":
			var rnote_file := File.new()
			if rnote_file.open(rnote_path, File.READ) == OK:
				var rnote_text := rnote_file.get_as_text()
				rnote_file.close()
				var rnote_parsed = JSON.parse(rnote_text)
				if rnote_parsed.error == OK and typeof(rnote_parsed.result) == TYPE_DICTIONARY:
					mesh_name = String(rnote_parsed.result.get("Name", ""))
		if mesh_name == "" and cfg.has("NoteSkin") and typeof(cfg.NoteSkin) == TYPE_DICTIONARY:
			var skin_cfg_path := String(cfg.NoteSkin.get("Value", ""))
			if skin_cfg_path != "":
				mesh_name = skin_cfg_path.get_file().get_basename()
		if mesh_name == "":
			mesh_name = note_path.get_file().get_basename()
		if mesh_name == "":
			mesh_name = "Imported Note Skin"

		var mesh_slug := _slugify(mesh_name)
		if mesh_slug == "":
			mesh_slug = "imported"

		if not dir.dir_exists(Globals.p("user://meshes")): dir.make_dir_recursive(Globals.p("user://meshes"))
		var mesh_dest_name := "%s.obj" % mesh_slug
		if _copy_file(note_path, "user://meshes/%s" % mesh_dest_name):
			var mtl_path := _find_file(root, "noteSkin", ["mtl"])
			if mtl_path != "":
				_copy_file(mtl_path, "user://meshes/%s.mtl" % mesh_slug)

			Rhythia.register_meshes()
			var mesh_id := "ugc_" + mesh_slug
			Rhythia.registry_mesh.add_item(NoteMesh.new(mesh_id, mesh_name + " (custom)", "user://meshes/%s" % mesh_dest_name, "???"))
			var mesh_item = Rhythia.registry_mesh.get_item(mesh_id)
			if mesh_item:
				Rhythia.select_mesh(mesh_item)
				result.imported.append("Note skin")
			else:
				result.errors.append("Note skin copied but couldn't be registered.")
		else:
			result.errors.append("Couldn't write note skin.")
	else:
		result.skipped.append("Note skin (none in archive)")

	var color_path := _find_file(root, "colorSet", ["txt"])
	if color_path != "":
		if not dir.dir_exists(Globals.p("user://colorsets")): dir.make_dir_recursive(Globals.p("user://colorsets"))
		var color_slug := _slugify(color_path.get_file().get_basename())
		if color_slug == "":
			color_slug = "imported"
		var color_dest_name := "%s.txt" % color_slug
		var color_dest := "user://colorsets/%s" % color_dest_name
		if _copy_file(color_path, color_dest):
			var color_id := "custom_" + color_slug
			Rhythia.load_color_txt(color_dest, color_id)
			var color_item = Rhythia.registry_colorset.get_item(color_id)
			if color_item:
				Rhythia.select_colorset(color_item)
				result.imported.append("Colorset")
			else:
				result.errors.append("Colorset copied but couldn't be registered.")
		else:
			result.errors.append("Couldn't write colorset.")
	else:
		result.skipped.append("Colorset (none in archive)")

	var bg_path := _find_first_image_recursive(root.plus_file("backgrounds"))
	if bg_path != "":
		var bg_ext := bg_path.get_extension().to_lower()
		var bg_dest := "user://custombg.%s" % bg_ext
		for ext in IMAGE_EXTS:
			dir.remove(Globals.p("user://panobg.%s" % ext))
		if _copy_file(bg_path, bg_dest):
			var bg_item = Rhythia.registry_world.get_item("ssp_custombg")
			if bg_item:
				Rhythia.select_world(bg_item)
				result.imported.append("Background")
			else:
				result.errors.append("Background copied but couldn't be selected.")
		else:
			result.errors.append("Couldn't write background.")
	else:
		result.skipped.append("Background (none in archive)")

	var hit_src := _find_file(root, "hitSound", SOUND_EXTS)
	var miss_src := _find_file(root, "missSound", SOUND_EXTS)
	var import_name := path.get_file().get_basename()
	if import_name == "":
		import_name = "Imported"

	if hit_src != "":
		var new_hit = Rhythia.create_named_sound_from_file("hit", import_name, hit_src)
		if new_hit:
			Rhythia.select_hit_sound(new_hit)
			result.imported.append("Hit sound")
		else:
			result.errors.append("Couldn't import hit sound.")
	else:
		result.skipped.append("Hit sound (none in archive)")

	if miss_src != "":
		var new_miss = Rhythia.create_named_sound_from_file("miss", import_name, miss_src)
		if new_miss:
			Rhythia.select_miss_sound(new_miss)
			result.imported.append("Miss sound")
		else:
			result.errors.append("Couldn't import miss sound.")
	else:
		result.skipped.append("Miss sound (none in archive)")

	_apply_value(cfg, "ApproachRate", "approach_rate", result, "Approach rate", SETTINGS_ROOT + "/Notes/Notes/Group/H/ApproachRate/ApproachRate")
	_apply_value(cfg, "SpawnDistance", "spawn_distance", result, "Spawn distance", SETTINGS_ROOT + "/Notes/Notes/Group/H/SpawnDist/SpawnDist")
	if cfg.has("CameraFov") and typeof(cfg.CameraFov) == TYPE_DICTIONARY and cfg.CameraFov.has("Value"):
		var fov_v := float(cfg.CameraFov.Value)
		if abs(fov_v - 72.1) < 0.01 or abs(fov_v - 72.5) < 0.01:
			cfg.CameraFov.Value = 70
	_apply_value(cfg, "CameraFov", "fov", result, "Camera FOV", SETTINGS_ROOT + "/Gameplay/Camera/Group/H/FOV/FOV")
	_apply_value(cfg, "FadeLength", "fade_length", result, "Fade length", SETTINGS_ROOT + "/Notes/Notes/Group/H/FadeLength/FadeLength", 100.0)
	_apply_value(cfg, "HalfGhost", "half_ghost", result, "Half ghost")
	_apply_value(cfg, "PushBack", "do_note_pushback", result, "Push back")
	_apply_value(cfg, "NoteOpacity", "note_opacity", result, "Note opacity", SETTINGS_ROOT + "/Notes/Notes/Group/H/NoteOpacity/NoteOpacity", 100.0)
	if cfg.has("NoteScale") and typeof(cfg.NoteScale) == TYPE_DICTIONARY and cfg.NoteScale.has("Value"):
		var scale_v := float(cfg.NoteScale.Value)
		if scale_v >= 0.9 and scale_v <= 1.0:
			cfg.NoteScale.Value = 1.0
	_apply_value(cfg, "NoteScale", "note_size", result, "Note scale", SETTINGS_ROOT + "/Notes/Notes/Group/H/NoteScale/NoteScale")
	_apply_value(cfg, "CursorScale", "cursor_scale", result, "Cursor scale", SETTINGS_ROOT + "/World & Cursor/Cursor/Group/H/CursorScale/CursorScale")
	_apply_value(cfg, "CursorSensitivity", "sensitivity", result, "Cursor sensitivity", SETTINGS_ROOT + "/Gameplay/Camera/Group/H/Sensitivity/Sensitivity")
	_apply_value(cfg, "CursorTrailEnabled", "cursor_trail", result, "Cursor trail enabled")

	if cfg.has("InvertMouse") and typeof(cfg.InvertMouse) == TYPE_DICTIONARY and cfg.InvertMouse.has("Value"):
		var invert_val = bool(cfg.InvertMouse.Value)
		Rhythia.invert_mouse = invert_val
		var invert_node = get_tree().get_root().get_node_or_null("Menu/Main/Maps/Results/Results/RS/H2/Mods/InvertMouse")
		if invert_node != null and invert_node is CheckBox:
			invert_node.pressed = invert_val
		result.imported.append("Invert mouse")

	if cfg.has("CursorColorRed") and cfg.has("CursorColorGreen") and cfg.has("CursorColorBlue"):
		Rhythia.cursor_color = Color8(
			int(cfg.CursorColorRed.Value), int(cfg.CursorColorGreen.Value), int(cfg.CursorColorBlue.Value)
		)
		Rhythia.cursor_color_type = Globals.CURSOR_CUSTOM_COLOR
		result.imported.append("Cursor color")

	_cleanup()
	emit_signal("import_finished", result)
	return result
