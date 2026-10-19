extends Reference

# Background layers: images/videos the player places around the screen in
# Settings > Background Editor. Shared by the editor and by gameplay
# (scripts/game/BgLayersGame.gd).
#
# Saved in user://bg_layers.json. Imported files are copied to user://bg_layers/.
# Every layer stores its centre (x, y) and size (w, h) as fractions of the
# screen, so the layout is the same at any resolution.

const DIR = "user://bg_layers"
const FILE = "user://bg_layers.json"
const MAX_LAYERS = 32

const IMAGE_EXTS = ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
# Godot 3's VideoPlayer can only play WebM (VP8/VP9) and Ogg Theora.
const VIDEO_EXTS = ["webm", "ogv"]

const FIT_COVER = "cover"
const FIT_STRETCH = "stretch"
const FIT_CONTAIN = "contain"

const PLACE_FRONT = "front"
const PLACE_BEHIND = "behind"

static func _p(path: String) -> String:
	if OS.has_feature("Android"):
		return path.replace("user://", OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP, false) + "/")
	return path

static func media_path(file_name: String) -> String:
	return _p(DIR).plus_file(file_name)

static func is_video_file(file_name: String) -> bool:
	return VIDEO_EXTS.has(file_name.get_extension().to_lower())

static func is_supported_file(file_name: String) -> bool:
	var ext = file_name.get_extension().to_lower()
	return IMAGE_EXTS.has(ext) or VIDEO_EXTS.has(ext)

static func default_data() -> Dictionary:
	return {"enabled": true, "placement": PLACE_FRONT, "layers": []}

static func new_layer(file_name: String, aspect: float) -> Dictionary:
	var screen_aspect = 16.0 / 9.0
	var h = 0.4
	var w = h * aspect / screen_aspect
	if w > 0.8:
		w = 0.8
		h = w * screen_aspect / max(aspect, 0.01)
	return {
		"file": file_name, "name": file_name,
		"x": 0.5, "y": 0.5, "w": w, "h": h, "rot": 0.0,
		"flip_h": false, "fit": FIT_STRETCH,
		"tint": "ffffff", "opacity": 1.0,
	}

static func _num(d: Dictionary, key: String, def: float, lo: float, hi: float) -> float:
	var v = d.get(key, def)
	if not (v is float or v is int):
		return def
	return clamp(float(v), lo, hi)

static func sanitize_layer(l) -> Dictionary:
	if not (l is Dictionary):
		return {}
	var file_name = str(l.get("file", "")).get_file()
	if file_name == "" or not is_supported_file(file_name):
		return {}
	var fit = str(l.get("fit", FIT_STRETCH))
	if not [FIT_COVER, FIT_STRETCH, FIT_CONTAIN].has(fit):
		fit = FIT_STRETCH
	var tint = str(l.get("tint", "ffffff"))
	if not tint.is_valid_html_color():
		tint = "ffffff"
	return {
		"file": file_name,
		"name": str(l.get("name", file_name)),
		"x": _num(l, "x", 0.5, -2.0, 3.0),
		"y": _num(l, "y", 0.5, -2.0, 3.0),
		"w": _num(l, "w", 0.3, 0.005, 5.0),
		"h": _num(l, "h", 0.3, 0.005, 5.0),
		"rot": _num(l, "rot", 0.0, -100000.0, 100000.0),
		"flip_h": bool(l.get("flip_h", false)),
		"fit": fit,
		"tint": tint,
		"opacity": _num(l, "opacity", 1.0, 0.0, 1.0),
	}

static func load_data() -> Dictionary:
	var d = default_data()
	var f = File.new()
	if not f.file_exists(_p(FILE)):
		return d
	if f.open(_p(FILE), File.READ) != OK:
		return d
	var txt = f.get_as_text()
	f.close()
	var res = JSON.parse(txt)
	if res.error != OK or not (res.result is Dictionary):
		return d
	var j: Dictionary = res.result
	d.enabled = bool(j.get("enabled", true))
	d.placement = PLACE_BEHIND if str(j.get("placement", PLACE_FRONT)) == PLACE_BEHIND else PLACE_FRONT
	var layers = j.get("layers", [])
	if layers is Array:
		for l in layers:
			var s = sanitize_layer(l)
			if not s.empty() and d.layers.size() < MAX_LAYERS:
				d.layers.append(s)
	return d

static func save_data(d: Dictionary) -> bool:
	var f = File.new()
	if f.open(_p(FILE), File.WRITE) != OK:
		return false
	f.store_string(JSON.print(d, "\t"))
	f.close()
	return true

# True when gameplay has something to draw (cheap check for Game.gd).
static func has_visible_layers() -> bool:
	var d = load_data()
	if not d.enabled:
		return false
	for l in d.layers:
		if l.opacity > 0.001:
			return true
	return false

# Copies an imported file into user://bg_layers/ and returns its new file name
# ("" on failure).
static func import_file(src: String) -> String:
	var ext = src.get_extension().to_lower()
	if not is_supported_file(src):
		return ""
	var dir = Directory.new()
	if not dir.dir_exists(_p(DIR)):
		dir.make_dir_recursive(_p(DIR))
	var base = src.get_file().get_basename()
	var clean = ""
	for i in base.length():
		var ch = base[i]
		if "\\/:*?\"<>|%#".find(ch) == -1:
			clean += ch
	clean = clean.strip_edges().substr(0, 40)
	if clean == "":
		clean = "media"
	var dst_name = "%s_%d%03d.%s" % [clean, OS.get_unix_time(), randi() % 1000, ext]
	if dir.copy(src, media_path(dst_name)) != OK:
		return ""
	return dst_name

static func delete_file(file_name: String):
	var dir = Directory.new()
	var path = media_path(file_name.get_file())
	if dir.file_exists(path):
		dir.remove(path)

# Checks the first bytes so a renamed/broken file never reaches the decoder.
static func _video_header_ok(path: String) -> bool:
	var f = File.new()
	if not f.file_exists(path) or f.open(path, File.READ) != OK:
		return false
	var b = f.get_buffer(4)
	f.close()
	if b.size() < 4:
		return false
	if path.get_extension().to_lower() == "webm":
		return b[0] == 0x1A and b[1] == 0x45 and b[2] == 0xDF and b[3] == 0xA3
	return b[0] == 0x4F and b[1] == 0x67 and b[2] == 0x67 and b[3] == 0x53 # "OggS"

# Builds the node for one layer under `parent`. Returns
# {"rect": TextureRect, "video": VideoPlayer or null, "ok": bool}.
# A missing/unsupported file gives ok = false and (when `placeholder` is set)
# a rect showing `placeholder`.
static func build_visual(l: Dictionary, parent: Node, placeholder: Texture = null, play_video: bool = true) -> Dictionary:
	var rect = TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand = true
	parent.add_child(rect)
	var out = {"rect": rect, "video": null, "ok": false}
	var path = media_path(l.get("file", ""))
	var f = File.new()
	if is_video_file(path):
		if _video_header_ok(path):
			var stream: VideoStream = null
			if path.get_extension().to_lower() == "webm":
				stream = VideoStreamWebm.new()
			else:
				stream = VideoStreamTheora.new()
			stream.set_file(path)
			var vp = VideoPlayer.new()
			vp.name = "Video"
			vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vp.expand = true
			vp.rect_size = Vector2(1, 1)
			vp.self_modulate = Color(1, 1, 1, 0) # only its texture is shown, by `rect`
			vp.volume_db = -80.0
			vp.stream = stream
			rect.add_child(vp)
			var tex = vp.get_video_texture()
			if tex != null and tex.get_width() > 0:
				rect.texture = tex
				out.video = vp
				out.ok = true
				# VideoPlayer has no loop option in Godot 3.
				vp.connect("finished", vp, "play")
				if play_video:
					vp.play()
			else:
				vp.queue_free()
	elif f.file_exists(path):
		var tex = Globals.imageLoader.load_file(path)
		# (an image the decoder rejects comes back as an empty 0x0 texture)
		if tex != null and tex != Globals.imageLoader.error_texture and tex != Globals.imageLoader.invalid_texture and tex.get_width() > 0:
			rect.texture = tex
			out.ok = true
	if not out.ok and placeholder != null:
		rect.texture = placeholder
	return out

# Positions a layer's rect inside a screen of `screen` pixels at `origin`.
static func apply_visual(rect: TextureRect, l: Dictionary, screen: Vector2, origin: Vector2 = Vector2()):
	if rect == null or not is_instance_valid(rect):
		return
	var size = Vector2(l.w * screen.x, l.h * screen.y)
	var center = origin + Vector2(l.x * screen.x, l.y * screen.y)
	rect.rect_rotation = 0
	rect.rect_size = size
	rect.rect_pivot_offset = size / 2.0
	rect.rect_position = center - size / 2.0
	rect.rect_rotation = l.rot
	rect.flip_h = l.flip_h
	match l.fit:
		FIT_COVER: rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		FIT_CONTAIN: rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_: rect.stretch_mode = TextureRect.STRETCH_SCALE
	var c = Color(l.tint)
	c.a = l.opacity
	rect.self_modulate = c
