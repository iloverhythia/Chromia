extends Reference

# Watching someone in a lobby with their settings (camera, notes, cursor, HUD,
# background...) instead of yours, without ever changing your own:
#
# - collect(): the settings this player sends when a round starts (what is on
#   their screen), as plain JSON values (colors as html text, content like the
#   colorset or note mesh as its id).
# - apply(their): your values are kept aside (in memory and in a backup file),
#   then theirs are set. Content you don't have (a custom colorset or mesh)
#   stays yours. Your device stays yours: window, sensitivity, audio, VR
#   setup... are never sent. In VR your camera stays yours; someone playing in
#   VR is shown with a still camera (parallax and spin mean nothing in VR).
# - restore(): your values back (leaving the song, starting a normal play).
# - Saving settings while theirs are on writes yours (Savia.save_settings uses
#   swap_out / swap_in), and a crash is covered by the backup file (recover()
#   at startup, after Sound Space Mode's).
#
# The game scene reads most settings when it is built, so switching between
# theirs and yours reloads the song scene straight into spectating (HUD.gd).

const BACKUP_FILE := "user://.spectate_backup.json"
const PREF_FILE := "user://spectate_view.txt"

# camera: left alone in VR
const CAMERA_KEYS := [
	"cam_unlock", "parallax", "ui_parallax", "grid_parallax", "fov",
	"hit_fov", "hit_fov_additive", "hit_fov_instant", "hit_fov_amplifier",
	"hit_fov_exponential", "hit_fov_decay", "faraway_hud", "camera_mode",
	"glow", "bloom", "vhs_shader",
]
# a VR player's beam, shown to a spectator who isn't in VR (in VR your own beam
# keeps your look)
const VR_LOOK_KEYS := ["vr_beam_color", "vr_beam_width", "vr_beam_rainbow"]
# what the notes, cursor, grid and HUD look like
const VIEW_KEYS := [
	"approach_rate", "spawn_distance", "fade_length", "note_size", "note_opacity",
	"note_spin_x", "note_spin_y", "note_spin_z", "half_ghost", "half_ghost_strength",
	"note_visual_approach", "visual_approach_follow", "do_note_pushback", "note_spawn_effect",
	"hitwindow_ms", "note_hitbox_size", "speed_hitwindow",
	"cursor_scale", "cursor_trail", "trail_detail", "trail_time", "trail_opacity",
	"trail_mode_scale", "trail_mode_opacity", "trail_gradient_enabled", "trail_gradient",
	"smart_trail", "enable_drift_cursor", "follow_drift_cursor", "edge_drift", "cursor_spin",
	"cursor_face_velocity", "cursor_color_type", "cursor_color",
	"cursor_glow", "cursor_glow_size", "cursor_glow_strength", "cursor_glow_pulse", "cursor_glow_trail",
	"cursor_glow_custom_color", "cursor_glow_color",
	"enable_grid", "enable_border", "border_color", "rainbow_grid", "custombg_color",
	"disable_bg_effects",
	"show_hp_bar", "show_timer", "show_left_panel", "show_right_panel", "attach_hp_to_grid",
	"attach_timer_to_grid", "rainbow_hud", "colorset_hud", "simple_hud", "show_accuracy_bar",
	"show_letter_grade", "show_fc_grade", "expand_hud_onhr", "score_popup", "billboard_score",
	"display_true_combo", "show_hit_effect", "show_miss_effect", "hit_effects_v2",
	"hit_effect_at_cursor",
	"panel_bg", "panel_text", "unpause_fill_color", "unpause_empty_color",
	"combo_fill_color", "combo_empty_color", "acc_fill_color", "acc_empty_color",
	"energy_fill_color", "energy_empty_color", "giveup_text", "giveup_fill_color",
	"giveup_fill_color_end_skip", "timer_text", "timer_text_done", "timer_text_canskip",
	"timer_fg", "timer_bg", "timer_fg_done", "timer_bg_done", "timer_fg_canskip",
	"timer_bg_canskip", "miss_flash_color", "pause_used_color", "miss_text_color",
	"pause_text_color", "score_text_color", "pause_ui_opacity", "grade_ss_saturation",
	"grade_ss_value", "grade_ss_shine", "grade_s_color", "grade_s_shine", "grade_a_color",
	"grade_b_color", "grade_c_color", "grade_d_color", "grade_f_color",
	"sound_space_mode", "ss_score_popups", "ss_health_y", "ss_health_w", "ss_progress_y",
	"ss_progress_w",
]
# content, sent as its id and looked up in your registries
const ID_KEYS := {
	"selected_colorset": "registry_colorset",
	"selected_mesh": "registry_mesh",
	"selected_space": "registry_world",
	"selected_hit_effect": "registry_effect",
	"selected_miss_effect": "registry_effect",
	"selected_border": "registry_border",
}
# set while theirs are on (their colorset is the one they had on screen)
const FORCED := {"random_colorset": false}
# someone playing in VR: a still camera
const FLAT_FOR_VR := {"cam_unlock": false, "parallax": 0.0, "ui_parallax": 0.0, "grid_parallax": 0.0}

static func all_keys() -> Array:
	var out: Array = CAMERA_KEYS + VIEW_KEYS + VR_LOOK_KEYS + ID_KEYS.keys() + FORCED.keys()
	return out

static func active() -> bool:
	return Rhythia.has_meta("spec_backup")

# whose settings are on (a lobby peer id), -1 for yours
static func applied_for() -> int:
	return int(Rhythia.get_meta("spec_for")) if active() and Rhythia.has_meta("spec_for") else -1

# --- your choice: their settings (default) or yours ----------------------------
static func prefer_theirs() -> bool:
	if Rhythia.has_meta("spec_pref"):
		return bool(Rhythia.get_meta("spec_pref"))
	var theirs := true
	var f := File.new()
	if f.open(Globals.p(PREF_FILE), File.READ) == OK:
		theirs = f.get_as_text().strip_edges() != "yours"
		f.close()
	Rhythia.set_meta("spec_pref", theirs)
	return theirs

static func set_prefer_theirs(theirs: bool):
	Rhythia.set_meta("spec_pref", theirs)
	var f := File.new()
	if f.open(Globals.p(PREF_FILE), File.WRITE) == OK:
		f.store_string("theirs" if theirs else "yours")
		f.close()

# --- sending ------------------------------------------------------------------
static func collect() -> Dictionary:
	var backup: Dictionary = Rhythia.get_meta("spec_backup") if active() else {}
	var out := {}
	for k in CAMERA_KEYS + VIEW_KEYS + VR_LOOK_KEYS + ID_KEYS.keys():
		if not (k in Rhythia):
			continue
		var v = backup[k] if backup.has(k) else Rhythia.get(k)
		var e = _enc(v)
		if typeof(e) != TYPE_NIL:
			out[k] = e
	out["_vr"] = bool(Rhythia.vr)
	out["_v"] = 1
	# your cursor picture, for whoever watches you with your settings (the
	# server keeps it by this hash: LobbyManager.upload_cursor_picture)
	var pic := own_cursor_file()
	if pic != "":
		out["cursor_image"] = File.new().get_sha256(pic)
	# your own border picture and note mesh (built-in ones every game has):
	# uploaded by LobbyManager.upload_spectate_assets, named here by hash
	var bfile := own_border_file(backup.get("selected_border", Rhythia.selected_border))
	if bfile != "":
		out["border_image"] = File.new().get_sha256(bfile)
	var mfile := own_mesh_file(backup.get("selected_mesh", Rhythia.selected_mesh))
	if mfile != "":
		out["mesh_file"] = File.new().get_sha256(mfile)
	# your backgrounds: the Custom Background picture / panorama and the
	# Background Editor's layers ("none": spectators see none of theirs either)
	for a in own_background_assets():
		out[a.key] = a.value
	return out

const MEDIA_MAX_BYTES := 20 * 1024 * 1024

# what a picture / video file really is, from its first bytes ("" if neither);
# the server names it the same way
static func media_ext(p: String) -> String:
	var f := File.new()
	if f.open(p, File.READ) != OK:
		return ""
	var b := f.get_buffer(12)
	f.close()
	if b.size() < 12:
		return ""
	if b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47: return "png"
	if b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF: return "jpg"
	if b[0] == 0x52 and b[1] == 0x49 and b[2] == 0x46 and b[3] == 0x46 and b[8] == 0x57 and b[9] == 0x45 and b[10] == 0x42 and b[11] == 0x50: return "webp"
	if b[0] == 0x47 and b[1] == 0x49 and b[2] == 0x46 and b[3] == 0x38: return "gif"
	if b[0] == 0x42 and b[1] == 0x4D: return "bmp"
	if b[0] == 0x1A and b[1] == 0x45 and b[2] == 0xDF and b[3] == 0xA3: return "webm"
	if b[0] == 0x4F and b[1] == 0x67 and b[2] == 0x67 and b[3] == 0x53: return "ogv"
	return ""

static func _file_size(p: String) -> int:
	var f := File.new()
	if f.open(p, File.READ) != OK:
		return 0
	var n := f.get_len()
	f.close()
	return n

static func _first_existing(base: String) -> String:
	var f := File.new()
	for e in ["png", "jpg", "jpeg", "webp", "bmp", "gif"]:
		if f.file_exists(base + "." + e):
			return base + "." + e
	return base if f.file_exists(base) else ""

# -> [{key, value, uploads: [[kind, file, sha]]}] for the settings and LobbyManager's upload
static func own_background_assets() -> Array:
	# (the settings and the upload both ask at a song's start: hashed once)
	if Rhythia.has_meta("own_bg_assets"):
		var cached: Dictionary = Rhythia.get_meta("own_bg_assets")
		if OS.get_ticks_msec() - int(cached.t) < 5000:
			return cached.value
	var out := _own_background_assets()
	Rhythia.set_meta("own_bg_assets", {"t": OS.get_ticks_msec(), "value": out})
	return out

static func _own_background_assets() -> Array:
	var out := []
	for pair in [["custombg_image", "user://custombg"], ["panobg_image", "user://panobg"]]:
		var p := _first_existing(Globals.p(pair[1]))
		var ext := media_ext(p) if p != "" else ""
		var size := _file_size(p) if p != "" else 0
		if ext == "" or size <= 0 or size > MEDIA_MAX_BYTES:
			out.append({"key": pair[0], "value": "none", "uploads": []})
		else:
			var sha: String = File.new().get_sha256(p)
			out.append({"key": pair[0], "value": "%s.%s" % [sha, ext], "uploads": [["media", p, sha]]})
	# the Background Editor: its media by hash, and the layout naming them
	var BG = load("res://scripts/BgLayers.gd")
	var d: Dictionary = BG.load_own_data()
	var layers := []
	var uploads := []
	if d.enabled:
		for l in d.layers:
			if l.opacity <= 0.001:
				continue
			var p: String = BG.own_media_path(l.file)
			var ext := media_ext(p)
			var size := _file_size(p)
			if ext == "" or size <= 0 or size > MEDIA_MAX_BYTES:
				continue
			var sha: String = File.new().get_sha256(p)
			var copy: Dictionary = l.duplicate()
			copy.file = "%s.%s" % [sha, ext]
			layers.append(copy)
			uploads.append(["media", p, sha])
	if layers.empty():
		out.append({"key": "bg_layers", "value": "none", "uploads": []})
	else:
		var layout_path: String = Globals.p(ASSET_CACHE).plus_file("own_bg_layers.json")
		Directory.new().make_dir_recursive(Globals.p(ASSET_CACHE))
		var f := File.new()
		if f.open(layout_path, File.WRITE) == OK:
			f.store_string(JSON.print({"enabled": true, "placement": d.placement, "layers": layers}))
			f.close()
			var lsha: String = File.new().get_sha256(layout_path)
			uploads.append(["bglayers", layout_path, lsha])
			out.append({"key": "bg_layers", "value": lsha, "uploads": uploads})
	return out

const ASSET_MAX_BYTES := 6 * 1024 * 1024
const ASSET_CACHE := "user://spectate_cache"

# your border's picture file, "" for a built-in border (or none)
static func own_border_file(b = null) -> String:
	if b == null:
		b = Rhythia.selected_border
	if b == null or not ("path" in b) or String(b.path) == "" or String(b.path).begins_with("res://"):
		return ""
	var base: String = Globals.p(String(b.path))
	var f := File.new()
	for p in [base, base + ".png", base + ".jpg", base + ".jpeg", base + ".webp", base + ".bmp"]:
		if f.file_exists(p) and not Directory.new().dir_exists(p):
			return p if _small_enough(p) else ""
	return ""

# your note mesh's .obj file, "" for a built-in mesh
static func own_mesh_file(m = null) -> String:
	if m == null:
		m = Rhythia.selected_mesh
	if m == null or not ("path" in m) or String(m.path) == "" or String(m.path).begins_with("res://"):
		return ""
	var p: String = Globals.p(String(m.path))
	if p.get_extension().to_lower() != "obj" or not File.new().file_exists(p):
		return ""
	return p if _small_enough(p) else ""

static func _small_enough(p: String) -> bool:
	var f := File.new()
	if f.open(p, File.READ) != OK:
		return false
	var n := f.get_len()
	f.close()
	return n > 0 and n <= ASSET_MAX_BYTES

# where a spectator keeps a downloaded one ("" when it isn't here yet)
static func cached_asset(sha: String, ext: String) -> String:
	sha = sha.to_lower()
	if sha.length() != 64 or not sha.is_valid_hex_number():
		return ""
	var p: String = Globals.p(ASSET_CACHE).plus_file("%s.%s" % [sha, ext])
	return p if File.new().file_exists(p) else ""

# your custom cursor picture (Settings: cursor), "" when it's the default one
# (an animated .gif cursor isn't sent)
static func own_cursor_file() -> String:
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var p: String = Globals.p("user://cursor." + ext)
		if File.new().file_exists(p):
			return p
	return ""

# --- applying -----------------------------------------------------------------
static func apply(their: Dictionary, peer_id: int):
	_ssm().end_song() # Sound Space Mode's look off first, so yours are what gets kept
	if active():
		_put(Rhythia.get_meta("spec_backup")) # back to yours, then theirs
	else:
		_take_backup()
	var keys: Array = VIEW_KEYS.duplicate()
	var their_vr := bool(their.get("_vr", false))
	if not Rhythia.vr:
		keys += VR_LOOK_KEYS
		if their_vr:
			for k in FLAT_FOR_VR:
				_assign(k, FLAT_FOR_VR[k])
		else:
			keys += CAMERA_KEYS
	for k in keys:
		if their.has(k) and (k in Rhythia):
			var v = _dec(their[k], Rhythia.get(k))
			if not (v is Dictionary and v.has("__skip")):
				_assign(k, v)
	for k in ID_KEYS:
		if their.has(k) and typeof(their[k]) == TYPE_STRING:
			var item = _lookup(k, their[k])
			if item != null:
				_assign(k, item)
	# their own border picture / mesh, once downloaded (LobbyManager fetches
	# them when their settings arrive); not here yet: the lookup above stands
	var bpath := cached_asset(String(their.get("border_image", "")), "png")
	if bpath != "":
		_assign("selected_border", Border.new("spectate_border", "Their border", "", bpath))
	var mpath := cached_asset(String(their.get("mesh_file", "")), "obj")
	if mpath != "":
		_assign("selected_mesh", NoteMesh.new("spectate_mesh", "Their mesh", mpath, ""))
	_apply_backgrounds(their)
	for k in FORCED:
		_assign(k, FORCED[k])
	Rhythia.set_meta("spec_for", peer_id)

# Their backgrounds (worlds/custom/custombg.gd and BgLayers.gd read these):
# "none" = they have none (so you don't see yours); not downloaded = yours stay.
static func _apply_backgrounds(their: Dictionary):
	_clear_backgrounds()
	for pair in [["custombg_image", "spec_custombg"], ["panobg_image", "spec_panobg"]]:
		var v := String(their.get(pair[0], ""))
		if v == "none":
			Rhythia.set_meta(pair[1], "")
		elif v.find(".") == 64:
			var p := cached_asset(v.left(64), v.right(65))
			if p != "":
				Rhythia.set_meta(pair[1], p)
	var lv := String(their.get("bg_layers", ""))
	if lv == "none":
		Rhythia.set_meta("spec_bg_layers", {"enabled": false, "placement": "front", "layers": []})
	elif lv != "":
		var lp := cached_asset(lv, "json")
		if lp != "":
			var f := File.new()
			if f.open(lp, File.READ) == OK:
				var parsed = JSON.parse(f.get_as_text())
				f.close()
				if parsed.error == OK and parsed.result is Dictionary:
					var BG = load("res://scripts/BgLayers.gd")
					var d := {"enabled": true, "placement": BG.PLACE_BEHIND if String(parsed.result.get("placement", "")) == BG.PLACE_BEHIND else BG.PLACE_FRONT, "layers": []}
					for l in parsed.result.get("layers", []):
						var s = BG.sanitize_layer(l)
						if not s.empty() and d.layers.size() < BG.MAX_LAYERS:
							d.layers.append(s)
					Rhythia.set_meta("spec_bg_layers", d)
					Rhythia.set_meta("spec_bg_dir", Globals.p(ASSET_CACHE))

static func _clear_backgrounds():
	for k in ["spec_custombg", "spec_panobg", "spec_bg_layers", "spec_bg_dir"]:
		if Rhythia.has_meta(k):
			Rhythia.remove_meta(k)

static func restore():
	_clear_backgrounds()
	if not active():
		return
	_ssm().end_song()
	_put(Rhythia.get_meta("spec_backup"))
	Rhythia.remove_meta("spec_backup")
	if Rhythia.has_meta("spec_for"):
		Rhythia.remove_meta("spec_for")
	Directory.new().remove(Globals.p(BACKUP_FILE))

# Savia.save_settings: yours while writing, theirs again after.
static func swap_out():
	if not active():
		return null
	var backup: Dictionary = Rhythia.get_meta("spec_backup")
	var cur := {}
	for k in backup:
		cur[k] = Rhythia.get(k)
	_put(backup)
	return cur

static func swap_in(cur):
	if cur is Dictionary:
		_put(cur)

# At startup: the game closed while someone else's settings were on. Put
# yours back (after Sound Space Mode's recover, which may have saved theirs).
static func recover():
	var f := File.new()
	var path: String = Globals.p(BACKUP_FILE)
	if active() or not f.file_exists(path):
		return
	if f.open(path, File.READ) != OK:
		return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	Directory.new().remove(path)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed.result
	for k in data:
		if not (k in Rhythia):
			continue
		if ID_KEYS.has(k):
			var item = _lookup(k, str(data[k]))
			if item != null:
				Rhythia.set(k, item)
		else:
			var v = _dec(data[k], Rhythia.get(k))
			if not (v is Dictionary and v.has("__skip")):
				Rhythia.set(k, v)
	Rhythia.save_settings()

# --- helpers ------------------------------------------------------------------
static func _ssm():
	return load("res://scripts/game/SoundSpaceMode.gd")

static func _take_backup():
	var backup := {}
	for k in all_keys():
		if k in Rhythia:
			backup[k] = Rhythia.get(k)
	# a random colorset is on for this song: yours is the one picked before it
	var before = Rhythia.get("_colorset_before_random")
	if before != null:
		backup["selected_colorset"] = before
		Rhythia.set("_colorset_before_random", null)
	Rhythia.set_meta("spec_backup", backup)
	var file_data := {}
	for k in backup:
		var e = _enc(backup[k])
		if typeof(e) != TYPE_NIL:
			file_data[k] = e
	var f := File.new()
	if f.open(Globals.p(BACKUP_FILE), File.WRITE) == OK:
		f.store_string(JSON.print(file_data))
		f.close()

static func _put(values: Dictionary):
	for k in values:
		_assign(k, values[k])

static func _assign(k: String, v):
	if k in Rhythia and typeof(v) != TYPE_NIL:
		Rhythia.set(k, v)

static func _lookup(k: String, id: String):
	var reg = Rhythia.get(ID_KEYS[k])
	if reg == null or id == "":
		return null
	var item = reg.get_item(id)
	return item if item else null

static func _enc(v):
	match typeof(v):
		TYPE_BOOL, TYPE_INT:
			return v
		TYPE_STRING:
			return v.left(200)
		TYPE_REAL:
			if is_nan(v):
				return 0.0
			if is_inf(v):
				return "inf" if v > 0 else "-inf"
			return v
		TYPE_COLOR:
			return "#" + v.to_html(true)
		TYPE_ARRAY:
			var out := []
			for x in v:
				if typeof(x) == TYPE_ARRAY:
					var inner := []
					for y in x:
						var e = _enc(y)
						if typeof(e) != TYPE_NIL and typeof(e) != TYPE_ARRAY:
							inner.append(e)
					out.append(inner)
				else:
					var e = _enc(x)
					if typeof(e) != TYPE_NIL:
						out.append(e)
			return out
		TYPE_OBJECT:
			if v != null and is_instance_valid(v) and "id" in v:
				return str(v.id)
	return null

# Their value read as the type of yours; {"__skip": true} if it doesn't fit.
static func _dec(v, cur):
	var num := typeof(v) == TYPE_BOOL or typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL
	match typeof(cur):
		TYPE_BOOL:
			if num: return bool(v)
		TYPE_INT:
			if num: return int(v)
		TYPE_REAL:
			if num: return float(v)
			if typeof(v) == TYPE_STRING and (v == "inf" or v == "-inf"):
				return INF if v == "inf" else -INF
		TYPE_COLOR:
			if typeof(v) == TYPE_STRING and v.is_valid_html_color():
				return Color(v)
		TYPE_STRING:
			if typeof(v) == TYPE_STRING: return v.left(200)
		TYPE_ARRAY:
			# the trail gradient: [[offset, "aarrggbb"], ...]
			if typeof(v) == TYPE_ARRAY and v.size() <= 16:
				var out := []
				for x in v:
					if typeof(x) != TYPE_ARRAY or x.size() != 2 or typeof(x[1]) != TYPE_STRING or not x[1].is_valid_html_color():
						return {"__skip": true}
					if not (typeof(x[0]) == TYPE_INT or typeof(x[0]) == TYPE_REAL):
						return {"__skip": true}
					out.append([clamp(float(x[0]), 0.0, 1.0), x[1]])
				return out
	return {"__skip": true}
