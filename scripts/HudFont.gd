extends Reference
# Settings > Fonts: the font of the song HUD (side panels, timer, combo,
# results text...). A few fonts come with the game, or your own .ttf / .otf
# (kept as user://hud_font.ttf or .otf). Spectators watching with your
# settings see it too: SpectateSettings sends the custom file by its hash
# (hud_font_file) and LobbyManager uploads / downloads it like a border picture.
#
# HUD.gd calls apply_hud() when a song starts: every text with its own font
# gets the chosen font in the same weight (bold stays bold), with the old font
# kept as a fallback for any letter the new one doesn't have.

const DEFAULT := "default"
const CUSTOM := "custom"
# id, name shown, files by weight (missing weights use "regular")
const FONTS := [
	["default", "Lato (Chromia's font)", {}],
	["roboto", "Roboto", {"regular": "res://assets/font/Roboto/Regular.ttf", "bold": "res://assets/font/Roboto/Bold.ttf",
		"light": "res://assets/font/Roboto/Light.ttf", "black": "res://assets/font/Roboto/Black.ttf"}],
	["ubuntu_mono", "Ubuntu Mono", {"regular": "res://assets/font/UbuntuMono/Regular.ttf", "bold": "res://assets/font/UbuntuMono/Bold.ttf"}],
	["press_start", "Press Start 2P (pixel)", {"regular": "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"}],
	["8bit", "8bitoperator (pixel)", {"regular": "res://assets/font/main.ttf"}],
	["noto_jp", "Noto Sans JP", {"regular": "res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"}],
	["custom", "Your own font", {}],
]
const CUSTOM_BASE := "user://hud_font"
const CUSTOM_EXTS := ["ttf", "otf"]
const MAX_BYTES := 4 * 1024 * 1024 # (what the server keeps for spectators)

static func ids() -> Array:
	var out := []
	for f in FONTS:
		out.append(f[0])
	return out

static func name_of(id: String) -> String:
	for f in FONTS:
		if f[0] == id:
			return f[1]
	return FONTS[0][1]

# your own font file, "" when there isn't one
static func custom_file() -> String:
	for ext in CUSTOM_EXTS:
		var p: String = Globals.p("%s.%s" % [CUSTOM_BASE, ext])
		if File.new().file_exists(p):
			return p
	return ""

static func remove_custom():
	for ext in CUSTOM_EXTS:
		var p: String = Globals.p("%s.%s" % [CUSTOM_BASE, ext])
		if File.new().file_exists(p):
			Directory.new().remove(p)

# copies a picked font in as your own -> "" or why it couldn't
static func set_custom(src: String) -> String:
	var ext := src.get_extension().to_lower()
	if not (ext in CUSTOM_EXTS):
		return "Pick a .ttf or .otf font."
	var f := File.new()
	if f.open(src, File.READ) != OK:
		return "Couldn't open that file."
	var n := f.get_len()
	var head := f.get_buffer(4)
	f.close()
	if n > MAX_BYTES:
		return "That font is too big (4 MB at most)."
	if not _looks_like_font(head):
		return "That isn't a .ttf or .otf font."
	if load_data(src) == null:
		return "That font couldn't be read."
	remove_custom()
	if Directory.new().copy(src, Globals.p("%s.%s" % [CUSTOM_BASE, ext])) != OK:
		return "Couldn't save the font."
	return ""

static func _looks_like_font(b: PoolByteArray) -> bool:
	if b.size() < 4:
		return false
	var tag := b.get_string_from_ascii()
	return tag == "OTTO" or tag == "true" or (b[0] == 0 and b[1] == 1 and b[2] == 0 and b[3] == 0)

static func load_data(path: String) -> DynamicFontData:
	if path == "" or not File.new().file_exists(path):
		return null
	var d := DynamicFontData.new()
	d.font_path = path
	# a font Godot can't read fails here, not in the middle of a song
	var test := DynamicFont.new()
	test.font_data = d
	test.size = 16
	if test.get_string_size("Aa").x <= 0:
		return null
	return d

# the font used now: yours, or the one of the player you're watching with
# their settings (SpectateSettings: spec_hud_font is their downloaded file)
static func current() -> Array:
	var id := String(Rhythia.get("hud_font"))
	if not (id in ids()):
		id = DEFAULT
	var custom := ""
	if id == CUSTOM:
		custom = String(Rhythia.get_meta("spec_hud_font")) if Rhythia.has_meta("spec_hud_font") else custom_file()
		if custom == "":
			id = DEFAULT
	return [id, custom]

static func _weight(fd: DynamicFontData) -> String:
	var p: String = String(fd.font_path).get_file().to_lower() if fd else ""
	if p.find("black") != -1 or p.find("heavy") != -1:
		return "black"
	if p.find("bold") != -1:
		return "bold"
	if p.find("light") != -1 or p.find("thin") != -1:
		return "light"
	return "regular"

# id + weight -> the font data to use (null: keep what's there)
static func data_for(id: String, custom: String, weight: String, cache: Dictionary) -> DynamicFontData:
	var key := "%s|%s|%s" % [id, custom, weight]
	if cache.has(key):
		return cache[key]
	var d: DynamicFontData = null
	if id == CUSTOM:
		d = load_data(custom)
	else:
		for f in FONTS:
			if f[0] == id and not f[2].empty():
				var files: Dictionary = f[2]
				var p: String = files.get(weight, files.get("regular", ""))
				if weight == "black" and not files.has("black"):
					p = files.get("bold", p)
				if p != "":
					d = load(p)
	cache[key] = d
	return d

const FONT_SLOTS := ["font", "normal_font", "bold_font"]

# every text under root with its own DynamicFont gets the chosen font
static func apply(root: Node, id := "", custom := ""):
	if id == "":
		var cur := current()
		id = cur[0]
		custom = cur[1]
	if id == DEFAULT or root == null:
		return
	var data_cache := {}
	var font_cache := {} # old DynamicFont -> new (fonts are shared between labels)
	_apply_to(root, id, custom, data_cache, font_cache)

static func _apply_to(n: Node, id: String, custom: String, data_cache: Dictionary, font_cache: Dictionary):
	if n is Control:
		for slot in FONT_SLOTS:
			if not n.has_font_override(slot):
				continue
			var old = n.get_font(slot)
			if not (old is DynamicFont) or old.font_data == null:
				continue
			if not font_cache.has(old):
				var d := data_for(id, custom, _weight(old.font_data), data_cache)
				if d == null:
					font_cache[old] = null
				else:
					var nf: DynamicFont = old.duplicate()
					nf.font_data = d
					# letters the new font doesn't have come from the old one
					nf.add_fallback(old.font_data)
					font_cache[old] = nf
			if font_cache[old] != null:
				n.add_font_override(slot, font_cache[old])
	for c in n.get_children():
		_apply_to(c, id, custom, data_cache, font_cache)

# HUD.gd, once the HUD is built (Sound Space Mode's panels keep their pixel font)
static func apply_hud(hud: Node):
	apply(hud)
