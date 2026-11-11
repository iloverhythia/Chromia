extends Reference

# Chromia skins (.cskin): everything you have on, in one file to share. Unlike a
# settings profile it carries the files too, and unlike Settings > Transfer it
# only holds your look, not your whole folder:
#
# - the look settings: notes, cursor, trail, grid, HUD, camera, colours, fonts,
#   panels, background brightness, avatar, VR hands / beam... (not your device:
#   window, sensitivity, volume, offset; not the rules: hit window, hitbox)
# - what's equipped: colorset, note mesh (or Note Builder mesh), border, hit /
#   miss sounds (custom ones as files), space, hit / miss effects
# - your custom files: cursor, trail and note pictures, fail / new best / menu
#   / loading sounds, Custom Background picture and panorama, the Background
#   Editor's layers with their pictures and videos, HUD font, HUD panel
#   picture, custom VR hand models
# - the menu's look (Settings > Menu Customizer, MenuStyle.gd): buttons,
#   sidebar, text colours and the background pattern
#
# Importing puts it all on (and turns off what the skin doesn't have, e.g. your
# custom cursor), after saving your look as "Before <skin>.cskin" in
# user://skins, which gives it back. The game then reloads like picking a
# profile. Content is added next to yours, never over it.
#
# File: "CHROMIASKIN1", u32 raw size, deflate(var2bytes({ v, kind: "cskin",
#   name, author, version, made, settings: {key: value}, slots: {slot: {ext,
#   data}}, content: {colorset|mesh|builder|border|hit_sound|miss_sound: {...}},
#   bg: {layout, media: {file: data}}, menu: {style, bg} })) (read back without
#   objects; skins from before the Menu Customizer have no menu and leave yours)

const MAGIC := "CHROMIASKIN1"
const EXT := "cskin"
const SKINS_DIR := "user://skins"
const MAX_FILE := 64 * 1024 * 1024
const MAX_TOTAL := 256 * 1024 * 1024

# the rules of play stay yours
const NOT_LOOK := ["hitwindow_ms", "note_hitbox_size", "speed_hitwindow"]
# look settings beyond what spectators get
const EXTRA_KEYS := ["vr_hand", "random_colorset", "hit_pitch", "hit_pitch_min", "hit_pitch_max",
	"play_hit_snd", "play_miss_snd", "sfx_2d", "alt_cam", "wave_menu", "wave_menu_colorset",
	"vr_menu_env"]
# what's equipped, by id (the settings file's names)
const ID_KEYS := ["selected_colorset", "selected_mesh", "selected_space", "selected_hit_effect",
	"selected_miss_effect", "selected_border_id", "selected_hit_sound_id", "selected_miss_sound_id"]

const IMAGE := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
const AUDIO := ["ogg", "mp3", "wav"]
const FONT := ["ttf", "otf"]
# single custom files in the user folder: base name -> the types it can be
const SLOTS := {
	"cursor": IMAGE, "trail": IMAGE, "note": IMAGE,
	"fail": AUDIO, "new_best": AUDIO, "menu": AUDIO, "loadingmusic": AUDIO,
	"hit": AUDIO, "miss": AUDIO,
	"custombg": IMAGE, "panobg": IMAGE,
	"hud_panel": ["png", "jpg", "jpeg", "webp"], "hud_font": FONT,
	"vr_hand": ["obj"], "vr_hand_left": ["obj"],
}

# the slots in words
const SLOT_NAMES := {
	"cursor": "cursor picture", "trail": "trail picture", "note": "note picture",
	"fail": "fail sound", "new_best": "new best sound", "menu": "menu music", "loadingmusic": "loading music",
	"hit": "hit sound", "miss": "miss sound", "custombg": "background picture", "panobg": "panorama",
	"hud_panel": "HUD panel picture", "hud_font": "HUD font", "vr_hand": "VR hand", "vr_hand_left": "left VR hand",
}

static func slot_words(slots: Array) -> String:
	var out := []
	for s in slots:
		out.append(SLOT_NAMES.get(s, s))
	return PoolStringArray(out).join(", ")

static func setting_keys() -> Array:
	var spec = load("res://scripts/SpectateSettings.gd")
	var out := []
	for k in spec.CAMERA_KEYS + spec.VIEW_KEYS + spec.VR_LOOK_KEYS + EXTRA_KEYS + ID_KEYS:
		if not NOT_LOOK.has(k) and not out.has(k):
			out.append(k)
	return out

# which slots a look uses (the others are left alone): s = its settings
static func slots_in_use(s: Dictionary) -> Array:
	var out := ["cursor", "trail", "note", "fail", "new_best", "menu", "loadingmusic"]
	# the plain hit / miss files only play with the "Default" sound picked
	if String(s.get("selected_hit_sound_id", "default")) in ["", "default"]:
		out.append("hit")
	if String(s.get("selected_miss_sound_id", "default")) in ["", "default"]:
		out.append("miss")
	if String(s.get("selected_space", "")) == "ssp_custombg":
		out += ["custombg", "panobg"]
	if String(s.get("hud_panel_style", "")) == "custom":
		out.append("hud_panel")
	if String(s.get("hud_font", "")) == "custom":
		out.append("hud_font")
	if String(s.get("vr_hand", "")) == "custom":
		out += ["vr_hand", "vr_hand_left"]
	return out

static func _slot_file(slot: String) -> String:
	var f := File.new()
	for e in SLOTS[slot]:
		var p: String = Globals.p("user://%s.%s" % [slot, e])
		if f.file_exists(p):
			return p
	return ""

static func _read(p: String):
	var f := File.new()
	if f.open(p, File.READ) != OK:
		return null
	var n := f.get_len()
	if n <= 0 or n > MAX_FILE:
		f.close()
		return null
	var b := f.get_buffer(n)
	f.close()
	return b

static func _write(p: String, data: PoolByteArray) -> bool:
	Directory.new().make_dir_recursive(p.get_base_dir())
	var f := File.new()
	if f.open(p, File.WRITE) != OK:
		return false
	f.store_buffer(data)
	f.close()
	return true

# the files directly in a folder: {name: bytes}
static func _folder(path: String) -> Dictionary:
	var out := {}
	var d := Directory.new()
	if d.open(path) != OK:
		return out
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir():
			var b = _read(path.plus_file(n))
			if b != null:
				out[n] = b
		n = d.get_next()
	d.list_dir_end()
	return out

static func _settings_now() -> Dictionary:
	Rhythia.save_settings() # (what's on now, in the file)
	var f := File.new()
	if f.open(Rhythia.get_startup_settings_path(), File.READ) != OK:
		return {}
	var parsed = parse_json(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

static func author_name() -> String:
	var c := ConfigFile.new()
	if c.load("user://settings.cfg") != OK:
		return ""
	var n = c.get_value("profile", "discord_display_name", "") if c.has_section_key("profile", "discord_display_name") else ""
	if String(n) == "" and c.has_section_key("profile", "discord_username"):
		n = c.get_value("profile", "discord_username", "")
	return String(n)

# --- Making one ---------------------------------------------------------------
# -> {bytes, data, parts: [what's in it], size} | {error}
static func build(skin_name: String) -> Dictionary:
	var all := _settings_now()
	if all.empty():
		return {"error": "Couldn't read your settings."}
	var settings := {}
	for k in setting_keys():
		if all.has(k):
			settings[k] = all[k]
	var parts := ["%d settings" % settings.size()]
	var total := 0
	var content := {}

	# the colorset: a custom one is a file in user://colorsets (its id is the
	# md5 of its file name)
	var cs_id := String(settings.get("selected_colorset", ""))
	if cs_id.begins_with("custom_"):
		var files = Globals.get_files_recursive([Globals.p("user://colorsets")], 5).files
		for p in files:
			if "custom_" + String(p).get_file().to_lower().md5_text() == cs_id:
				var b = _read(p)
				if b != null:
					content["colorset"] = {"name": String(p).get_file(), "data": b}
					parts.append("colorset")
				break
	# the note mesh: from user://meshes (+ its .mtl) or the Note Builder
	var mesh_id := String(settings.get("selected_mesh", ""))
	var NB = load("res://scripts/ui/settings/NoteBuilderMesh.gd")
	var slot = NB.slot_of(mesh_id)
	if slot != null:
		var files := _folder(NB.dir_path(slot))
		if files.has(NB.OBJ_FILE):
			content["builder"] = {"files": files}
			parts.append("Note Builder mesh")
	else:
		var m = Rhythia.registry_mesh.get_item(mesh_id) if Rhythia.registry_mesh != null else null
		if m != null and "path" in m and String(m.path).get_extension().to_lower() == "obj" and not String(m.path).begins_with("res://"):
			var obj = _read(String(m.path))
			if obj != null:
				var mtl = _read(String(m.path).get_basename() + ".mtl")
				content["mesh"] = {"name": String(m.path).get_file(), "obj": obj, "mtl": mtl if mtl != null else PoolByteArray()}
				parts.append("note mesh")
	# a custom border / hit sound / miss sound: its folder
	for e in [["border", "selected_border_id", "registry_border"], ["hit_sound", "selected_hit_sound_id", "registry_hit_sound"], ["miss_sound", "selected_miss_sound_id", "registry_miss_sound"]]:
		var reg = Rhythia.get(e[2])
		var item = reg.get_item(String(settings.get(e[1], ""))) if reg != null else null
		if item != null and "path" in item and String(item.path) != "" and not String(item.path).begins_with("res://"):
			var files := _folder(Globals.p(String(item.path)).get_base_dir())
			if not files.empty():
				content[e[0]] = {"slug": String(item.id), "name": String(item.name), "files": files}
				parts.append(String(e[0]).replace("_", " "))
	for c in content.values():
		for k in ["data", "obj", "mtl"]:
			if c.has(k):
				total += c[k].size()
		if c.has("files"):
			for b in c.files.values():
				total += b.size()

	# single files: cursor, sounds, pictures, font...
	var slots := {}
	for s in slots_in_use(settings):
		var p := _slot_file(s)
		if p == "":
			continue
		var b = _read(p)
		if b != null:
			slots[s] = {"ext": p.get_extension().to_lower(), "data": b}
			total += b.size()
	if not slots.empty():
		parts.append(slot_words(slots.keys()))

	# the Background Editor
	var BG = load("res://scripts/BgLayers.gd")
	var d: Dictionary = BG.load_own_data()
	var bg := {"layout": {"enabled": d.enabled, "placement": d.placement, "layers": []}, "media": {}}
	for l in d.layers:
		var b = _read(BG.own_media_path(l.file))
		if b == null:
			continue
		bg.layout.layers.append(l)
		bg.media[String(l.file)] = b
		total += b.size()
	if not bg.layout.layers.empty():
		parts.append("%d background layer%s" % [bg.layout.layers.size(), "" if bg.layout.layers.size() == 1 else "s"])
	if total > MAX_TOTAL:
		return {"error": "Your look is too big for one file (%s, 256 MB at most)." % load("res://scripts/SettingsTransfer.gd").human_size(total)}

	var data := {
		"v": 1, "kind": "cskin",
		"name": skin_name.strip_edges().left(80),
		"author": author_name().left(80),
		"version": str(ProjectSettings.get_setting("application/config/version")),
		"made": OS.get_unix_time(),
		"settings": settings, "slots": slots, "content": content, "bg": bg,
		"menu": load("res://scripts/ui/menu/MenuStyle.gd").data().duplicate(true),
	}
	var raw: PoolByteArray = var2bytes(data)
	var packed := PoolByteArray()
	packed.append_array(MAGIC.to_ascii())
	var head := StreamPeerBuffer.new()
	head.put_u32(raw.size())
	packed.append_array(head.data_array)
	packed.append_array(raw.compress(File.COMPRESSION_DEFLATE))
	return {"bytes": packed, "data": data, "parts": parts, "size": total}

static func save_to(path: String, skin_name: String) -> Dictionary:
	var b := build(skin_name)
	if b.has("error"):
		return b
	if not _write(path, b.bytes):
		return {"error": "Couldn't write %s." % path.get_file()}
	return b

# --- Reading one --------------------------------------------------------------
# -> {data} | {error}; everything in it checked, nothing trusted
static func read(bytes: PoolByteArray) -> Dictionary:
	var ml := MAGIC.length()
	if bytes.size() < ml + 4 or bytes.subarray(0, ml - 1).get_string_from_ascii() != MAGIC:
		return {"error": "That isn't a Chromia skin (.cskin)."}
	var head := StreamPeerBuffer.new()
	head.data_array = bytes.subarray(ml, ml + 3)
	var raw_size: int = head.get_u32()
	if raw_size <= 0 or raw_size > MAX_TOTAL * 2:
		return {"error": "The skin is damaged."}
	var raw: PoolByteArray = bytes.subarray(ml + 4, bytes.size() - 1).decompress(raw_size, File.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return {"error": "The skin is damaged."}
	var data = bytes2var(raw, false)
	if not (data is Dictionary) or String(data.get("kind", "")) != "cskin" or not (data.get("settings") is Dictionary):
		return {"error": "The skin is damaged."}
	var out := {
		"name": _clean_name(String(data.get("name", "")), "Skin"),
		"author": String(data.get("author", "")).left(80),
		"version": String(data.get("version", "")).left(40),
		"settings": {}, "slots": {}, "content": {}, "bg": {},
	}
	if data.get("menu") is Dictionary:
		out.menu = load("res://scripts/ui/menu/MenuStyle.gd").clean(data.menu)
	var allowed := setting_keys()
	for k in data.settings:
		var v = data.settings[k]
		if allowed.has(k) and typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING, TYPE_ARRAY, TYPE_DICTIONARY]:
			out.settings[k] = v
	if data.get("slots") is Dictionary:
		for s in data.slots:
			var e = data.slots[s]
			if SLOTS.has(s) and e is Dictionary and e.get("data") is PoolByteArray and SLOTS[s].has(String(e.get("ext", ""))) and e.data.size() > 0:
				out.slots[s] = {"ext": String(e.ext), "data": e.data}
	var c = data.get("content")
	if c is Dictionary:
		var cs = c.get("colorset")
		if cs is Dictionary and cs.get("data") is PoolByteArray and _ext_ok(String(cs.get("name", "")), ["txt", "json"]):
			out.content.colorset = {"name": _clean_name(String(cs.name), "colorset.txt"), "data": cs.data}
		var m = c.get("mesh")
		if m is Dictionary and m.get("obj") is PoolByteArray and m.obj.size() > 0:
			out.content.mesh = {"name": _clean_name(String(m.get("name", "")).get_basename(), "mesh") + ".obj", "obj": m.obj,
				"mtl": m.mtl if m.get("mtl") is PoolByteArray else PoolByteArray()}
		for k in ["builder", "border", "hit_sound", "miss_sound"]:
			var e = c.get(k)
			if not (e is Dictionary) or not (e.get("files") is Dictionary):
				continue
			var files := {}
			for fname in e.files:
				if e.files[fname] is PoolByteArray and _clean_name(String(fname), "") == String(fname):
					files[String(fname)] = e.files[fname]
			if not files.empty():
				out.content[k] = {"slug": _slug(String(e.get("slug", k))), "name": String(e.get("name", "")).left(80), "files": files}
	var bg = data.get("bg")
	if bg is Dictionary and bg.get("layout") is Dictionary and bg.get("media") is Dictionary:
		var BG = load("res://scripts/BgLayers.gd")
		var layers := []
		var media := {}
		for l in bg.layout.get("layers", []):
			var s: Dictionary = BG.sanitize_layer(l)
			if s.empty() or not (bg.media.get(s.file) is PoolByteArray) or layers.size() >= BG.MAX_LAYERS:
				continue
			layers.append(s)
			media[s.file] = bg.media[s.file]
		out.bg = {"layout": {"enabled": bool(bg.layout.get("enabled", true)),
			"placement": BG.PLACE_BEHIND if String(bg.layout.get("placement", "")) == BG.PLACE_BEHIND else BG.PLACE_FRONT,
			"layers": layers}, "media": media}
	return {"data": out}

static func read_file(path: String) -> Dictionary:
	var b = _read(path) if path != "" else null
	if b == null:
		var f := File.new()
		if f.file_exists(path) and f.open(path, File.READ) == OK and f.get_len() > MAX_FILE:
			f.close()
			return {"error": "That skin is too big."}
		return {"error": "Couldn't open %s." % path.get_file()}
	return read(b)

# what a skin holds, in words
static func describe(d: Dictionary) -> String:
	var parts := ["%d settings" % d.settings.size()]
	for k in ["colorset", "mesh", "builder", "border", "hit_sound", "miss_sound"]:
		if d.content.has(k):
			parts.append({"colorset": "colorset", "mesh": "note mesh", "builder": "Note Builder mesh", "border": "border", "hit_sound": "hit sound", "miss_sound": "miss sound"}[k])
	if not d.slots.empty():
		parts.append(slot_words(d.slots.keys()))
	if d.bg.has("layout") and not d.bg.layout.layers.empty():
		parts.append("%d background layer%s" % [d.bg.layout.layers.size(), "" if d.bg.layout.layers.size() == 1 else "s"])
	if d.has("menu") and not (d.menu.style.empty() and d.menu.bg.empty()):
		parts.append("a customized menu")
	return PoolStringArray(parts).join(", ")

static func _ext_ok(n: String, exts: Array) -> bool:
	return exts.has(n.get_extension().to_lower())

# a plain file name (no folders, nothing odd)
static func _clean_name(n: String, fallback: String) -> String:
	n = n.get_file().strip_edges()
	var out := ""
	for i in n.length():
		if "\\/:*?\"<>|%#".find(n[i]) == -1 and n.ord_at(i) >= 32:
			out += n[i]
	out = out.left(80)
	if out == "" or out.begins_with(".") or not out.is_valid_filename():
		return fallback
	return out

static func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if "abcdefghijklmnopqrstuvwxyz0123456789_".find(ch) != -1:
			out += ch
	return out.left(40) if out != "" else "skin"

# --- Putting one on -----------------------------------------------------------
# a free name in a folder (the same file already there is used as it is)
static func _free_path(dir_path: String, file_name: String, data: PoolByteArray) -> String:
	var p := dir_path.plus_file(file_name)
	var n := 2
	var f := File.new()
	while f.file_exists(p):
		if f.get_sha256(p) == _sha(data):
			return p
		p = dir_path.plus_file("%s %d.%s" % [file_name.get_basename(), n, file_name.get_extension()])
		n += 1
	return p

static func _sha(data: PoolByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(data)
	return c.finish().hex_encode()

# a free folder for a border / sound / builder mesh (the same files: reused)
static func _free_folder(parent: String, slug: String, files: Dictionary) -> String:
	var d := Directory.new()
	var name := slug
	var n := 2
	while d.dir_exists(parent.plus_file(name)):
		var same := true
		for fname in files:
			var p := parent.plus_file(name).plus_file(fname)
			if not File.new().file_exists(p) or File.new().get_sha256(p) != _sha(files[fname]):
				same = false
				break
		if same:
			return name
		name = "%s_%d" % [slug, n]
		n += 1
	return name

static func _write_folder(path: String, files: Dictionary) -> bool:
	var ok := true
	for fname in files:
		ok = _write(path.plus_file(fname), files[fname]) and ok
	return ok

# Puts the skin on (the caller reloads the game after). Your look first goes
# into user://skins/Before <name>.cskin. -> {before, written} | {error}
static func apply(d: Dictionary) -> Dictionary:
	var skins: String = Globals.p(SKINS_DIR)
	Directory.new().make_dir_recursive(skins)
	var before_path := skins.plus_file(_clean_name("Before %s.%s" % [d.name, EXT], "Before skin." + EXT))
	var before := save_to(before_path, "Before " + d.name)
	if before.has("error"):
		return {"error": "Couldn't save your look first, so nothing was changed: " + String(before.error)}

	var startup: String = Rhythia.get_startup_settings_path()
	var merged := {}
	var f := File.new()
	if f.open(startup, File.READ) == OK:
		var parsed = parse_json(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			merged = parsed
	for k in d.settings:
		merged[k] = d.settings[k]
	var written := 0

	# equipped content, added next to yours
	var c: Dictionary = d.content
	if c.has("colorset"):
		var p := _free_path(Globals.p("user://colorsets"), c.colorset.name, c.colorset.data)
		if _write(p, c.colorset.data):
			merged["selected_colorset"] = "custom_" + p.get_file().to_lower().md5_text()
			written += 1
	if c.has("mesh"):
		var p := _free_path(Globals.p("user://meshes"), c.mesh.name, c.mesh.obj)
		if _write(p, c.mesh.obj):
			if c.mesh.mtl.size() > 0:
				_write(p.get_basename() + ".mtl", c.mesh.mtl)
			merged["selected_mesh"] = "ugc_" + p.get_file().to_lower().replace(" ", "_")
			written += 1
	if c.has("builder"):
		var NB = load("res://scripts/ui/settings/NoteBuilderMesh.gd")
		var parent: String = Globals.p(NB.DIR).plus_file(NB.SLOTS_DIR)
		var slot := _free_folder(parent, "skin_" + _slug(d.name), c.builder.files)
		if _write_folder(parent.plus_file(slot), c.builder.files):
			merged["selected_mesh"] = NB.mesh_id(slot)
			written += 1
	for e in [["border", "user://borders", "selected_border_id"], ["hit_sound", "user://hitsounds", "selected_hit_sound_id"], ["miss_sound", "user://misssounds", "selected_miss_sound_id"]]:
		if not c.has(e[0]):
			continue
		var parent: String = Globals.p(e[1])
		var slug := _free_folder(parent, c[e[0]].slug, c[e[0]].files)
		if _write_folder(parent.plus_file(slug), c[e[0]].files):
			merged[e[2]] = slug
			written += 1

	# single files: the skin's, and yours off where it has none
	for s in slots_in_use(merged):
		for ext in SLOTS[s]:
			var p: String = Globals.p("user://%s.%s" % [s, ext])
			if f.file_exists(p):
				Directory.new().remove(p)
		if d.slots.has(s):
			if _write(Globals.p("user://%s.%s" % [s, d.slots[s].ext]), d.slots[s].data):
				written += 1

	# the Background Editor: the skin's layers (none if it has none)
	var BG = load("res://scripts/BgLayers.gd")
	var layout: Dictionary = BG.default_data()
	if d.bg.has("layout"):
		layout = d.bg.layout.duplicate(true)
		for file_name in d.bg.media:
			var p: String = BG.own_media_path(file_name)
			if not f.file_exists(p) or f.get_sha256(p) != _sha(d.bg.media[file_name]):
				if _write(p, d.bg.media[file_name]):
					written += 1
	BG.save_data(layout)

	# the menu's look (Menu Customizer), when the skin has one: only saved, the
	# menu that opens after the reload puts it on. (Restyling the whole open
	# menu right before the reload flooded the engine's message queue in VR:
	# a black screen until the game was restarted.)
	if d.has("menu"):
		var MS = load("res://scripts/ui/menu/MenuStyle.gd")
		MS.save(MS.clean(d.menu))

	for path in [startup, Globals.p("user://settings.json")]:
		if f.open(path, File.WRITE) == OK:
			f.store_string(to_json(merged))
			f.close()
	return {"before": before_path, "written": written}
