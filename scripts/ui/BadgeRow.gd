extends HFlowContainer

# A player's badges (the in-game profile, Spectate > View stats), the same as
# on their website profile: the server works the list out with the website's
# own files (savia_web server/src/sitebadges.js: roles, tag, Ranker, Map of
# the Day tier, the admins' badges) and draws each badge's picture. Here each
# is the website's tile: the drawing on a dark square tinted with the badge's
# colour, its name, description and note when you hover it.
# An older server (no badge_list): the old chips.

const SITE := "https://savia.nysr.host"
const ICON_DIR := "user://badge_icons"
const MOTD_TIERS = [[100, "Prismatic"], [60, "Supernova"], [30, "Eclipse"], [15, "Golden Sun"], [5, "Sunshine"], [1, "Sunrise"]]
const TILE_BG := Color("#121316")
const PAD := 3.0 # (the picture's margin past the 24-unit drawing: sitebadges.js PAD)

var _font: Font
var _k := 1.0

static func make(p: Dictionary, font: Font, k: float = 1.0) -> Control:
	var row = load("res://scripts/ui/BadgeRow.gd").new()
	row._font = font
	row._k = k
	row.add_constant_override("hseparation", int(6 * k))
	row.add_constant_override("vseparation", int(6 * k))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var list = p.get("badge_list")
	if list is Array:
		for b in list:
			if b is Dictionary:
				row._tile(b)
	else:
		row._old_chips(p)
	row.visible = row.get_child_count() > 0
	return row

# --- the website's tiles -------------------------------------------------------

class Tile extends PanelContainer:
	const TILE_BG := Color("#121316")
	var title := ""
	var desc := ""
	var note := ""
	var font: Font
	var col := Color.white
	var k := 1.0
	var _sb: StyleBoxFlat

	func _ready():
		connect("mouse_entered", self, "_hover", [true])
		connect("mouse_exited", self, "_hover", [false])

	func _hover(on: bool):
		# (website: the tile 13% -> 20% of its colour, the edge 50% -> 80%)
		_sb.bg_color = TILE_BG.linear_interpolate(Color(col.r, col.g, col.b), 0.20 if on else 0.13)
		_sb.border_color = Color(col.r, col.g, col.b, 0.8 if on else 0.5)

	# the website's hover box: the name in bold, the description, the note small
	func _make_custom_tooltip(_t):
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1c1e23")
		sb.border_color = Color(1, 1, 1, 0.12)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(8 * k))
		sb.content_margin_left = 9 * k
		sb.content_margin_right = 9 * k
		sb.content_margin_top = 6 * k
		sb.content_margin_bottom = 6 * k
		pc.add_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_constant_override("separation", int(2 * k))
		pc.add_child(v)
		for part in [[title, Color("#f4f4f5"), 1.0], [desc if desc != title else "", Color("#d4d4d4"), 0.92], [note, Color("#8f8f96"), 0.85]]:
			if String(part[0]) == "":
				continue
			var l := Label.new()
			l.text = String(part[0])
			l.align = Label.ALIGN_CENTER
			l.add_color_override("font_color", part[1])
			if font is DynamicFont:
				var f: DynamicFont = font.duplicate()
				f.size = int(max(8, round(font.size * float(part[2]))))
				l.add_font_override("font", f)
			v.add_child(l)
		return pc

func _tile(b: Dictionary):
	var t := Tile.new()
	t.title = Globals.s(b.get("name", ""))
	t.desc = Globals.s(b.get("desc", ""))
	t.note = Globals.s(b.get("note", ""))
	t.font = _font
	t.k = _k
	var c := Globals.s(b.get("color", ""))
	t.col = Color(c) if c.is_valid_html_color() else Color("#9dbcf0")
	t.hint_tooltip = t.title # (the box itself: _make_custom_tooltip)
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.rect_min_size = Vector2(30, 30) * _k
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(round(7 * _k)))
	for side in [MARGIN_LEFT, MARGIN_RIGHT, MARGIN_TOP, MARGIN_BOTTOM]:
		sb.set_default_margin(side, 0)
	t._sb = sb
	t.add_stylebox_override("panel", sb)
	t._hover(false)
	# the drawing: 19 px for its 24 units, with the margin around it
	var px: float = 19.0 * _k * (24.0 + 2.0 * PAD) / 24.0
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(cc)
	var tr := TextureRect.new()
	tr.expand = true
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.rect_min_size = Vector2(px, px)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(tr)
	add_child(t)
	_icon(Globals.s(b.get("icon", "")), tr)

# the badge pictures: kept (in memory and in the user folder) once fetched
static func _cache() -> Dictionary:
	var root = Engine.get_main_loop().root
	if not root.has_meta("badge_icon_cache"):
		root.set_meta("badge_icon_cache", {})
	return root.get_meta("badge_icon_cache")

func _icon(url: String, tr: TextureRect):
	if not url.begins_with("/savia-public/api/badge-icon/"):
		return
	var name := url.get_file()
	var cache := _cache()
	if cache.has(name):
		tr.texture = cache[name]
		return
	var path: String = Globals.p(ICON_DIR).plus_file(name)
	if File.new().file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			cache[name] = _tex(img)
			tr.texture = cache[name]
			return
	if not is_inside_tree():
		_waiting.append([url, tr]) # (asked for once the row is on screen)
		return
	var r := HTTPRequest.new()
	r.timeout = 15
	add_child(r)
	r.connect("request_completed", self, "_on_icon", [r, name, path, tr])
	if r.request(SITE + url) != OK:
		r.queue_free()

var _waiting := []
func _ready():
	var w := _waiting
	_waiting = []
	for x in w:
		if is_instance_valid(x[1]):
			_icon(x[0], x[1])

func _on_icon(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, name: String, path: String, tr: TextureRect):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		return
	Directory.new().make_dir_recursive(Globals.p(ICON_DIR))
	var f := File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_buffer(body)
		f.close()
	var tex := _tex(img)
	_cache()[name] = tex
	if is_instance_valid(tr):
		tr.texture = tex

static func _tex(img: Image) -> ImageTexture:
	var t := ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return t

# --- an older server: chips ------------------------------------------------------

func _old_chips(p: Dictionary):
	var motd := int(p.get("motd_count", 0))
	if motd > 0:
		var tier := "Sunrise"
		for t in MOTD_TIERS:
			if motd >= int(t[0]):
				tier = t[1]
				break
		_chip("%s  x%d" % [tier, motd], Color(1, 0.86, 0.2), "Map of the Day: completed %d map%s of the day" % [motd, "" if motd == 1 else "s"])
	if bool(p.get("is_ranker", false)):
		_chip("Ranker", Color(0.55, 0.85, 1.0), "Ranks maps")
	var badges = p.get("badges", [])
	if badges is Array:
		for b in badges:
			if not (b is Dictionary):
				continue
			var cols = b.get("colors", [])
			var col := Color(0.8, 0.7, 1.0)
			if cols is Array and cols.size() > 0 and String(cols[0]).is_valid_html_color():
				col = Color(String(cols[0]))
			_chip(Globals.s(b.get("name", "Badge")), col, Globals.s(b.get("desc", "")))

func _chip(text: String, col: Color, tip: String):
	var k := _k
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.18 + 0.05, col.g * 0.18 + 0.05, col.b * 0.18 + 0.06, 0.95)
	sb.border_color = Color(col.r, col.g, col.b, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(6 * k))
	sb.content_margin_left = 8 * k
	sb.content_margin_right = 8 * k
	sb.content_margin_top = 2 * k
	sb.content_margin_bottom = 2 * k
	pc.add_stylebox_override("panel", sb)
	pc.hint_tooltip = tip
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := Label.new()
	l.text = text
	if _font != null:
		l.add_font_override("font", _font)
	l.add_color_override("font_color", col.lightened(0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	add_child(pc)
