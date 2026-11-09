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
# id, name shown, files by weight (missing weights use "regular"), group in
# Settings > Fonts
const FONTS := [
	["default", "Lato (Chromia's font)", {}, "Clean"],
	["roboto", "Roboto", {"regular": "res://assets/font/Roboto/Regular.ttf", "bold": "res://assets/font/Roboto/Bold.ttf",
		"light": "res://assets/font/Roboto/Light.ttf", "black": "res://assets/font/Roboto/Black.ttf"}, "Clean"],
	["poppins", "Poppins", {"regular": "res://assets/font/Poppins/Poppins-Regular.ttf", "bold": "res://assets/font/Poppins/Poppins-Bold.ttf", "light": "res://assets/font/Poppins/Poppins-Light.ttf", "black": "res://assets/font/Poppins/Poppins-Black.ttf"}, "Clean"],
	["montserrat", "Montserrat", {"regular": "res://assets/font/Montserrat/Montserrat-Regular.ttf", "bold": "res://assets/font/Montserrat/Montserrat-Bold.ttf", "black": "res://assets/font/Montserrat/Montserrat-Black.ttf"}, "Clean"],
	["nunito", "Nunito", {"regular": "res://assets/font/Nunito/Nunito-Regular.ttf", "bold": "res://assets/font/Nunito/Nunito-Bold.ttf", "black": "res://assets/font/Nunito/Nunito-ExtraBold.ttf"}, "Clean"],
	["kanit", "Kanit", {"regular": "res://assets/font/Kanit/Kanit-Regular.ttf", "bold": "res://assets/font/Kanit/Kanit-Bold.ttf", "light": "res://assets/font/Kanit/Kanit-Light.ttf", "black": "res://assets/font/Kanit/Kanit-Black.ttf"}, "Clean"],
	["barlow", "Barlow", {"regular": "res://assets/font/Barlow/Barlow-Regular.ttf", "bold": "res://assets/font/Barlow/Barlow-Bold.ttf", "light": "res://assets/font/Barlow/Barlow-Light.ttf", "black": "res://assets/font/Barlow/Barlow-Black.ttf"}, "Clean"],
	["titillium", "Titillium Web", {"regular": "res://assets/font/TitilliumWeb/TitilliumWeb-Regular.ttf", "bold": "res://assets/font/TitilliumWeb/TitilliumWeb-Bold.ttf", "light": "res://assets/font/TitilliumWeb/TitilliumWeb-Light.ttf", "black": "res://assets/font/TitilliumWeb/TitilliumWeb-Black.ttf"}, "Clean"],
	["lexend", "Lexend", {"regular": "res://assets/font/Lexend/Lexend-Regular.ttf", "bold": "res://assets/font/Lexend/Lexend-Bold.ttf", "light": "res://assets/font/Lexend/Lexend-Light.ttf", "black": "res://assets/font/Lexend/Lexend-Black.ttf"}, "Clean"],
	["quicksand", "Quicksand (rounded)", {"regular": "res://assets/font/Quicksand/Quicksand-Regular.ttf", "bold": "res://assets/font/Quicksand/Quicksand-Bold.ttf", "light": "res://assets/font/Quicksand/Quicksand-Light.ttf"}, "Clean"],
	["fredoka", "Fredoka (rounded)", {"regular": "res://assets/font/Fredoka/Fredoka-Regular.ttf", "bold": "res://assets/font/Fredoka/Fredoka-Bold.ttf", "light": "res://assets/font/Fredoka/Fredoka-Light.ttf"}, "Clean"],
	["noto_jp", "Noto Sans JP", {"regular": "res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"}, "Clean"],
	["bebas", "Bebas Neue", {"regular": "res://assets/font/BebasNeue/BebasNeue-Regular.ttf"}, "Tall and narrow"],
	["oswald", "Oswald", {"regular": "res://assets/font/Oswald/Oswald-Regular.ttf", "bold": "res://assets/font/Oswald/Oswald-Bold.ttf", "light": "res://assets/font/Oswald/Oswald-Light.ttf"}, "Tall and narrow"],
	["teko", "Teko", {"regular": "res://assets/font/Teko/Teko-Regular.ttf", "bold": "res://assets/font/Teko/Teko-Bold.ttf", "light": "res://assets/font/Teko/Teko-Light.ttf"}, "Tall and narrow"],
	["rajdhani", "Rajdhani", {"regular": "res://assets/font/Rajdhani/Rajdhani-Regular.ttf", "bold": "res://assets/font/Rajdhani/Rajdhani-Bold.ttf"}, "Tall and narrow"],
	["orbitron", "Orbitron", {"regular": "res://assets/font/Orbitron/Orbitron-Regular.ttf", "bold": "res://assets/font/Orbitron/Orbitron-Bold.ttf", "black": "res://assets/font/Orbitron/Orbitron-Black.ttf"}, "Sci-fi and tech"],
	["exo2", "Exo 2", {"regular": "res://assets/font/Exo2/Exo2-Regular.ttf", "bold": "res://assets/font/Exo2/Exo2-Bold.ttf", "light": "res://assets/font/Exo2/Exo2-Light.ttf", "black": "res://assets/font/Exo2/Exo2-Black.ttf"}, "Sci-fi and tech"],
	["oxanium", "Oxanium", {"regular": "res://assets/font/Oxanium/Oxanium-Regular.ttf", "bold": "res://assets/font/Oxanium/Oxanium-Bold.ttf", "light": "res://assets/font/Oxanium/Oxanium-Light.ttf", "black": "res://assets/font/Oxanium/Oxanium-Black.ttf"}, "Sci-fi and tech"],
	["chakra", "Chakra Petch", {"regular": "res://assets/font/ChakraPetch/ChakraPetch-Regular.ttf", "bold": "res://assets/font/ChakraPetch/ChakraPetch-Bold.ttf", "light": "res://assets/font/ChakraPetch/ChakraPetch-Light.ttf"}, "Sci-fi and tech"],
	["audiowide", "Audiowide", {"regular": "res://assets/font/Audiowide/Audiowide-Regular.ttf"}, "Sci-fi and tech"],
	["michroma", "Michroma (wide)", {"regular": "res://assets/font/Michroma/Michroma-Regular.ttf"}, "Sci-fi and tech"],
	["electrolize", "Electrolize", {"regular": "res://assets/font/Electrolize/Electrolize-Regular.ttf"}, "Sci-fi and tech"],
	["zendots", "Zen Dots", {"regular": "res://assets/font/ZenDots/ZenDots-Regular.ttf"}, "Sci-fi and tech"],
	["turret", "Turret Road", {"regular": "res://assets/font/TurretRoad/TurretRoad-Regular.ttf", "bold": "res://assets/font/TurretRoad/TurretRoad-Bold.ttf", "light": "res://assets/font/TurretRoad/TurretRoad-Light.ttf"}, "Sci-fi and tech"],
	["russo", "Russo One", {"regular": "res://assets/font/RussoOne/RussoOne-Regular.ttf"}, "Sci-fi and tech"],
	["blackops", "Black Ops One (stencil)", {"regular": "res://assets/font/BlackOpsOne/BlackOpsOne-Regular.ttf"}, "Sci-fi and tech"],
	["press_start", "Press Start 2P (pixel)", {"regular": "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"}, "Pixel and monospace"],
	["8bit", "8bitoperator (pixel)", {"regular": "res://assets/font/main.ttf"}, "Pixel and monospace"],
	["silkscreen", "Silkscreen (pixel)", {"regular": "res://assets/font/Silkscreen/Silkscreen-Regular.ttf", "bold": "res://assets/font/Silkscreen/Silkscreen-Bold.ttf"}, "Pixel and monospace"],
	["pixelify", "Pixelify Sans (pixel)", {"regular": "res://assets/font/PixelifySans/PixelifySans-Regular.ttf", "bold": "res://assets/font/PixelifySans/PixelifySans-Bold.ttf"}, "Pixel and monospace"],
	["vt323", "VT323 (old terminal)", {"regular": "res://assets/font/VT323/VT323-Regular.ttf"}, "Pixel and monospace"],
	["ubuntu_mono", "Ubuntu Mono", {"regular": "res://assets/font/UbuntuMono/Regular.ttf", "bold": "res://assets/font/UbuntuMono/Bold.ttf"}, "Pixel and monospace"],
	["jetbrains_mono", "JetBrains Mono", {"regular": "res://assets/font/JetBrainsMono/JetBrainsMono-Regular.ttf", "bold": "res://assets/font/JetBrainsMono/JetBrainsMono-Bold.ttf", "light": "res://assets/font/JetBrainsMono/JetBrainsMono-Light.ttf", "black": "res://assets/font/JetBrainsMono/JetBrainsMono-Black.ttf"}, "Pixel and monospace"],
	["space_mono", "Space Mono", {"regular": "res://assets/font/SpaceMono/SpaceMono-Regular.ttf", "bold": "res://assets/font/SpaceMono/SpaceMono-Bold.ttf"}, "Pixel and monospace"],
	["share_tech_mono", "Share Tech Mono", {"regular": "res://assets/font/ShareTechMono/ShareTechMono-Regular.ttf"}, "Pixel and monospace"],
	["major_mono", "Major Mono Display", {"regular": "res://assets/font/MajorMonoDisplay/MajorMonoDisplay-Regular.ttf"}, "Pixel and monospace"],
	["bungee", "Bungee", {"regular": "res://assets/font/Bungee/Bungee-Regular.ttf"}, "Fun and loud"],
	["righteous", "Righteous", {"regular": "res://assets/font/Righteous/Righteous-Regular.ttf"}, "Fun and loud"],
	["bangers", "Bangers (comic)", {"regular": "res://assets/font/Bangers/Bangers-Regular.ttf"}, "Fun and loud"],
	["comic_neue", "Comic Neue", {"regular": "res://assets/font/ComicNeue/ComicNeue-Regular.ttf", "bold": "res://assets/font/ComicNeue/ComicNeue-Bold.ttf", "light": "res://assets/font/ComicNeue/ComicNeue-Light.ttf"}, "Fun and loud"],
	["monoton", "Monoton (neon lines)", {"regular": "res://assets/font/Monoton/Monoton-Regular.ttf"}, "Fun and loud"],
	["creepster", "Creepster (spooky)", {"regular": "res://assets/font/Creepster/Creepster-Regular.ttf"}, "Fun and loud"],
	["lobster", "Lobster", {"regular": "res://assets/font/Lobster/Lobster-Regular.ttf"}, "Fun and loud"],
	["pacifico", "Pacifico (script)", {"regular": "res://assets/font/Pacifico/Pacifico-Regular.ttf"}, "Fun and loud"],
	["caveat", "Caveat (handwriting)", {"regular": "res://assets/font/Caveat/Caveat-Regular.ttf", "bold": "res://assets/font/Caveat/Caveat-Bold.ttf"}, "Fun and loud"],
	["custom", "Your own font", {}, ""],
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

# Settings > Fonts > Size: the HUD's text this much bigger or smaller (1 = as made)
static func size_scale() -> float:
	var v = Rhythia.get("hud_font_size")
	return clamp(float(v) / 100.0, 0.5, 2.0) if v != null else 1.0

# every text under root with its own DynamicFont gets the chosen font (and size)
static func apply(root: Node, id := "", custom := ""):
	if id == "":
		var cur := current()
		id = cur[0]
		custom = cur[1]
	var scale := size_scale()
	if root == null or (id == DEFAULT and abs(scale - 1.0) < 0.001):
		return
	var data_cache := {}
	var font_cache := {} # old DynamicFont -> new (fonts are shared between labels)
	_apply_to(root, id, custom, data_cache, font_cache, scale)

static func _apply_to(n: Node, id: String, custom: String, data_cache: Dictionary, font_cache: Dictionary, scale: float = 1.0):
	if n is Control:
		for slot in FONT_SLOTS:
			if not n.has_font_override(slot):
				continue
			var old = n.get_font(slot)
			if not (old is DynamicFont) or old.font_data == null:
				continue
			if not font_cache.has(old):
				var d: DynamicFontData = old.font_data if id == DEFAULT else data_for(id, custom, _weight(old.font_data), data_cache)
				if d == null and abs(scale - 1.0) > 0.001:
					d = old.font_data # (only the size changes)
				if d == null:
					font_cache[old] = null
				else:
					var nf: DynamicFont = old.duplicate()
					if d != old.font_data:
						nf.font_data = d
						# letters the new font doesn't have come from the old one
						nf.add_fallback(old.font_data)
					if abs(scale - 1.0) > 0.001:
						nf.size = int(max(4, round(old.size * scale)))
						nf.outline_size = int(round(old.outline_size * scale))
					font_cache[old] = nf
			if font_cache[old] != null:
				n.add_font_override(slot, font_cache[old])
	for c in n.get_children():
		_apply_to(c, id, custom, data_cache, font_cache, scale)

# HUD.gd, once the HUD is built (Sound Space Mode's panels keep their pixel font)
static func apply_hud(hud: Node):
	apply(hud)
