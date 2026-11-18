extends Node
class_name RhsImporter

signal import_finished(result)

const IMAGE_EXTS = ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
const SOUND_EXTS = ["ogg", "mp3", "wav"]

const TMP_ZIP := "user://tmp_rhs_import.zip"
const TMP_DIR := "user://tmp_rhs_import"
const RHYTHIA_VIEW := 0.943 # how much of what Chromia's camera sees Rhythia's does, at the same FOV (measured)

func _real_path(user_path: String) -> String:
	return user_path.replace("user://", OS.get_user_data_dir() + "/")

# A .rhs is a zip. It used to be unpacked with Windows' tar.exe, so skins
# could only be imported on Windows; ZipReader reads it on every device.
func _extract_zip(zip_path: String, dest_dir: String, exec_log: Dictionary) -> bool:
	var dir := Directory.new()
	dir.make_dir_recursive(dest_dir)
	var f := File.new()
	if f.open(zip_path, File.READ) != OK:
		exec_log.output = "the file couldn't be opened"
		return false
	var bytes := f.get_buffer(f.get_len())
	f.close()
	var files: Dictionary = load("res://scripts/content/ZipReader.gd").read(bytes)
	if files.empty():
		exec_log.output = "it isn't a zip archive"
		return false
	for name in files:
		var rel := String(name).replace("\\", "/")
		if rel.ends_with("/") or rel.find("..") != -1 or rel.begins_with("/"):
			continue
		var out := dest_dir.plus_file(rel)
		dir.make_dir_recursive(out.get_base_dir())
		var w := File.new()
		if w.open(out, File.WRITE) == OK:
			w.store_buffer(files[name])
			w.close()
	exec_log.exit_code = 0
	return true

# "<prefix>Red" / "Green" / "Blue" of a Rhythia config (0-255) as a colour, or null
func _cfg_color(cfg: Dictionary, prefix: String, alpha: float = 1.0):
	for c in ["Red", "Green", "Blue"]:
		if not (cfg.get(prefix + c) is Dictionary) or not cfg[prefix + c].has("Value"):
			return null
	return Color(float(cfg[prefix + "Red"].Value) / 255.0, float(cfg[prefix + "Green"].Value) / 255.0, float(cfg[prefix + "Blue"].Value) / 255.0, alpha)

func _cfg(cfg: Dictionary, key: String, def = null):
	var e = cfg.get(key)
	return e.Value if e is Dictionary and e.has("Value") else def

# The rest of a Rhythia skin: its cursor, trail and border pictures, the
# settings Chromia has too, and the whole config kept for the Rhythia look
# (game/RhythiaLook.gd: the song's HUD as Rhythia draws it).
func _import_look(cfg: Dictionary, root: String, result: Dictionary, import_name: String, full_look: bool = true):
	var dir := Directory.new()
	# the cursor's picture and the trail's
	for it in [["cursorSkin", "cursor", "Cursor picture"], ["cursorTrailSkin", "trail", "Trail picture"]]:
		var src := _find_file(root, it[0], IMAGE_EXTS)
		if src == "":
			continue
		for ext in IMAGE_EXTS:
			dir.remove(Globals.p("user://%s.%s" % [it[1], ext]))
		if _copy_file(src, "user://%s.%s" % [it[1], src.get_extension().to_lower()]):
			result.imported.append(it[2])
	# the border's picture, colour and see-through
	var bsrc := _find_file(root, "borderSkin", IMAGE_EXTS)
	if bsrc != "":
		var b = Rhythia.create_border_from_file("%s (Rhythia)" % import_name, bsrc)
		if b != null:
			Rhythia.select_border(b)
			Rhythia.enable_border = true
			result.imported.append("Border")
	var bc = _cfg_color(cfg, "BorderColor", clamp(float(_cfg(cfg, "BorderOpacity", 1.0)), 0.0, 1.0))
	if bc != null:
		Rhythia.border_color = bc
	# settings both games have
	for it in [["Parallax", "parallax"], ["GridParallax", "grid_parallax"], ["CursorTrailOpacity", "trail_opacity"],
			["CursorTrailShrinkOverTime", "trail_mode_scale"], ["CursorTrailGradientEnabled", "trail_gradient_enabled"]]:
		var v = _cfg(cfg, it[0])
		if v != null and it[1] in Rhythia:
			Rhythia.set(it[1], v)
	var fade = _cfg(cfg, "CursorTrailFadeTimeSeconds")
	if fade != null:
		Rhythia.trail_time = clamp(float(fade), 0.01, 2.0)
	var grad = _cfg(cfg, "CursorTrailGradient")
	if grad is Array and grad.size() >= 2:
		var stops := []
		for g in grad:
			if g is Dictionary:
				stops.append([clamp(float(g.get("Position", 0.0)), 0.0, 1.0), Color(float(g.get("Red", 255)) / 255.0, float(g.get("Green", 255)) / 255.0, float(g.get("Blue", 255)) / 255.0).to_html(true)])
		if stops.size() >= 2:
			Rhythia.trail_gradient = stops
	var op = _cfg(cfg, "CursorOpacity")
	if op != null:
		Rhythia.cursor_color.a = clamp(float(op), 0.0, 1.0)
	if String(_cfg(cfg, "HitEffect", "")) == "none":
		Rhythia.show_hit_effect = false
	if _cfg(cfg, "MissEffectOpacity") != null and float(_cfg(cfg, "MissEffectOpacity")) <= 0.0:
		Rhythia.show_miss_effect = false
	var grid_a = _cfg(cfg, "PlayfieldGridOpacity")
	if _cfg(cfg, "PlayfieldGridEnabled") != null:
		Rhythia.enable_grid = bool(_cfg(cfg, "PlayfieldGridEnabled")) and (grid_a == null or float(grid_a) > 0.0)
	if not full_look:
		return
	# --- Rhythia's look (the "Full" import) ---
	# Rhythia's camera sees less than Chromia's at the same FOV (the grid is
	# bigger on its screen): the FOV that shows the grid at Rhythia's size
	var rf = _cfg(cfg, "CameraFov")
	if rf != null and float(rf) >= 10.0 and float(rf) <= 150.0:
		var view_fov: float = rad2deg(2.0 * atan(tan(deg2rad(float(rf)) / 2.0) * RHYTHIA_VIEW))
		_sync_range_control(SETTINGS_ROOT + "/Gameplay/Camera/Group/H/FOV/FOV", view_fov)
		Rhythia.fov = view_fov # (after the slider, which rounds it)
	# Rhythia's half ghost leaves more of a note than Chromia's usual 80% fade
	# (a note four fifths of the way in was still at two thirds in its picture)
	if bool(_cfg(cfg, "HalfGhost", false)):
		_sync_range_control(SETTINGS_ROOT + "/Notes/Notes/Group/H/HalfGhostStrength/Strength", 50.0) # (its box in Settings writes the setting)
		Rhythia.half_ghost_strength = 0.5
	# the song's HUD as Rhythia has it: every part shows, and the look decides which
	for k in ["show_left_panel", "show_right_panel", "show_timer", "show_hp_bar"]:
		Rhythia.set(k, true)
	Rhythia.simple_hud = false
	Rhythia.attach_hp_to_grid = false
	Rhythia.attach_timer_to_grid = false
	Rhythia.show_config = false
	# a plain background when none of Rhythia's own is on (the look colours it)
	var plain := true
	for k in ["BackgroundTunnelEnabled", "BackgroundSineEnabled", "BackgroundChevronEnabled", "BackgroundRaysEnabled", "BackgroundGridEnabled"]:
		plain = plain and not bool(_cfg(cfg, k, false))
	var imgs = _cfg(cfg, "BackgroundImages", [])
	if plain and not (imgs is Array and not imgs.empty()):
		var void_world = Rhythia.registry_world.get_item("ssp_void")
		if void_world != null:
			Rhythia.select_world(void_world)
	var RL = load("res://scripts/game/RhythiaLook.gd")
	RL.save_config(cfg)
	Rhythia.ss_hud = false
	Rhythia.hud_panel_style = RL.STYLE
	result.imported.append("Rhythia's look for the song's HUD")

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
	var node = Rhythia.menu_node(ui_path.trim_prefix("Menu/"))
	if node != null and node is Range:
		node.value = value

func _apply_value(cfg: Dictionary, key: String, rhythia_var: String, result: Dictionary, label: String, ui_path: String = "", ui_scale: float = 1.0):
	if cfg.has(key) and typeof(cfg[key]) == TYPE_DICTIONARY and cfg[key].has("Value"):
		var v = cfg[key].Value
		Rhythia.set(rhythia_var, v)
		_sync_range_control(ui_path, float(v) * ui_scale)
		result.imported.append(label)

# full_look: Rhythia's look for the song as well (its HUD, its camera's reach,
# its plain background), not only the settings and pictures both games have
func import_rhs(path: String, full_look: bool = true) -> Dictionary:
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

			# (the id the game gives a file in user://meshes at every start: with
			# another one the skin's note was back to the default after a restart)
			var mesh_id := "ugc_" + mesh_dest_name.to_lower().replace(" ", "_")
			if Rhythia.registry_mesh.get_item(mesh_id) == null:
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
		var invert_node = Rhythia.menu_node("Main/Maps/Results/Results/RS/H2/Mods/InvertMouse")
		if invert_node != null and invert_node is CheckBox:
			invert_node.pressed = invert_val
		result.imported.append("Invert mouse")

	if cfg.has("CursorColorRed") and cfg.has("CursorColorGreen") and cfg.has("CursorColorBlue"):
		Rhythia.cursor_color = Color8(
			int(cfg.CursorColorRed.Value), int(cfg.CursorColorGreen.Value), int(cfg.CursorColorBlue.Value)
		)
		Rhythia.cursor_color_type = Globals.CURSOR_CUSTOM_COLOR
		result.imported.append("Cursor color")

	_import_look(cfg, root, result, import_name, full_look)

	# Nothing above saves: the imported skin/settings were lost on the next start.
	if result.imported.size() > 0:
		Rhythia.save_settings()
	_cleanup()
	emit_signal("import_finished", result)
	return result
