extends Node

# Settings > Menu Customizer (MenuCustomTab.gd): your own look for the menu.
# Button colours, roundness and border, text and text box colours, the
# sidebar's colours, the menu's tint, and the background pattern behind it
# (WaveMenuBG.gd draws it: contour lines, grid, dots, waves, hexagons,
# stripes, stars or a plain colour, in your colours and speed).
#
# Kept in user://menu_style.json: { style: {key: "#rrggbbaa" | number},
#   bg: {pattern, colors: ["#..", "#..", "#.."], speed} }. Only what you
# changed is kept; the rest is the game's own look. Skins (Skin.gd) carry it,
# so exporting a skin exports your menu too.
#
# The look is put on the shared menu theme (uitheme.tres) and the sidebar's
# own styles at run time, so every menu button follows it without a restart.
# The theme's own looks are remembered first, so Reset gives them back.
# One of these sits in the menu (WaveMenuBG adds it); it redoes the sidebar
# when the menu is rebuilt.

const FILE := "user://menu_style.json"
const THEME := "res://uitheme.tres"

# the patterns, in the order the customizer lists them
const PATTERNS := ["contour", "grid", "dots", "waves", "hex", "stripes", "stars", "solid", "off"]
const PATTERN_NAMES := {
	"contour": "Contour lines", "grid": "Grid", "dots": "Dots", "waves": "Waves", "hex": "Hexagons",
	"stripes": "Stripes", "stars": "Starfield", "solid": "Plain colour", "off": "Off (the 3D background)",
}
# the pattern colours when you haven't picked any: background, lines, accent
const PATTERN_COLORS := [Color(0.07, 0.03, 0.08), Color(0.46, 0.2, 0.42), Color(1.0, 0.45, 0.62)]

# what can be changed, with the game's own look (null: read from the menu itself)
const KEYS := {
	"btn_bg": Color(0.764706, 0.65098, 0.8),
	"btn_hover": Color(0.913725, 0.74902, 0.94902),
	"btn_text": Color(0, 0, 0),
	"btn_radius": 6,
	"btn_border": Color(1, 1, 1, 0.35),
	"btn_border_w": 0,
	"text": Color(1, 1, 1),
	"field_bg": Color(0.639216, 0.576471, 0.658824),
	"field_text": Color(0, 0, 0),
	"focus": Color(0, 0.976471, 1, 0.313726),
	"sidebar_bg": Color(0, 0, 0),
	"sidebar_sel": Color(0.0588235, 0.0588235, 0.0588235),
	"sidebar_icon": Color(1, 1, 1),
	"menu_tint": Color(0.0156863, 0.0156863, 0.0156863, 0.392157),
}

# --- the saved look --------------------------------------------------------------

static func data() -> Dictionary:
	if Engine.has_meta("menu_style_data"):
		return Engine.get_meta("menu_style_data")
	var d := {"style": {}, "bg": {}}
	var f := File.new()
	if f.open(Globals.p(FILE), File.READ) == OK:
		var parsed = parse_json(f.get_as_text())
		f.close()
		d = clean(parsed)
	Engine.set_meta("menu_style_data", d)
	return d

# what came from a file or a skin -> only known keys, sane values
static func clean(raw) -> Dictionary:
	var out := {"style": {}, "bg": {}}
	if not (raw is Dictionary):
		return out
	var s = raw.get("style", {})
	if s is Dictionary:
		for k in KEYS:
			if not s.has(k):
				continue
			if KEYS[k] is Color:
				var v := String(s[k])
				if v.is_valid_html_color():
					out.style[k] = v
			elif typeof(s[k]) in [TYPE_INT, TYPE_REAL]:
				out.style[k] = int(clamp(float(s[k]), 0, 30))
	var b = raw.get("bg", {})
	if b is Dictionary:
		var pat := String(b.get("pattern", ""))
		if PATTERNS.has(pat):
			out.bg.pattern = pat
		var cols = b.get("colors", [])
		if cols is Array and cols.size() == 3:
			var ok := true
			for c in cols:
				ok = ok and String(c).is_valid_html_color()
			if ok:
				out.bg.colors = [String(cols[0]), String(cols[1]), String(cols[2])]
		if typeof(b.get("speed")) in [TYPE_INT, TYPE_REAL]:
			out.bg.speed = clamp(float(b.speed), 0.0, 4.0)
	return out

static func save(d: Dictionary):
	Engine.set_meta("menu_style_data", d)
	var f := File.new()
	if f.open(Globals.p(FILE), File.WRITE) == OK:
		f.store_string(to_json(d))
		f.close()

# a value: yours, else the game's
static func get_value(key: String):
	var s: Dictionary = data().style
	var def = KEYS[key]
	if not s.has(key):
		return def
	if def is Color:
		return Color(String(s[key]))
	return int(s[key])

static func set_value(key: String, v):
	var d := data()
	if v == null:
		d.style.erase(key)
	elif v is Color:
		d.style[key] = v.to_html(true)
	else:
		d.style[key] = int(v)
	save(d)

static func bg_pattern() -> String:
	return String(data().bg.get("pattern", "contour"))

# the pattern's colours: yours, or [] when you haven't picked (the pattern's own)
static func bg_colors() -> Array:
	var c = data().bg.get("colors", [])
	return [Color(c[0]), Color(c[1]), Color(c[2])] if c is Array and c.size() == 3 else []

static func bg_speed() -> float:
	return float(data().bg.get("speed", 1.0))

static func set_bg(key: String, v):
	var d := data()
	if v == null:
		d.bg.erase(key)
	elif key == "colors":
		d.bg.colors = [v[0].to_html(true), v[1].to_html(true), v[2].to_html(true)]
	else:
		d.bg[key] = v
	save(d)

static func reset():
	save({"style": {}, "bg": {}})

# put a look on (a skin's, or a file's): saved, then shown
static func put_on(raw, tree: SceneTree):
	save(clean(raw))
	refresh(tree)

# show the saved look everywhere now
static func refresh(tree: SceneTree):
	apply_theme()
	if tree != null:
		tree.call_group("menu_style", "restyle")

# --- the theme (every button, text box and label using uitheme.tres) -------------

static func _orig(theme: Theme) -> Dictionary:
	if theme.has_meta("menu_style_orig"):
		return theme.get_meta("menu_style_orig")
	var o := {}
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb = theme.get_stylebox(st, "Button")
		o["Button/" + st] = sb.duplicate() if sb != null else null
	for st in ["normal", "focus"]:
		var sb = theme.get_stylebox(st, "LineEdit")
		o["LineEdit/" + st] = sb.duplicate() if sb != null else null
	for c in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]:
		o["Button/" + c] = theme.get_color(c, "Button")
	o["Label/font_color"] = theme.get_color("font_color", "Label")
	o["LineEdit/font_color"] = theme.get_color("font_color", "LineEdit")
	theme.set_meta("menu_style_orig", o)
	return o

static func _radius(sb: StyleBoxFlat, r: int):
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r

static func _border(sb: StyleBoxFlat, w: int, c: Color):
	sb.border_width_left = w
	sb.border_width_right = w
	sb.border_width_top = w
	sb.border_width_bottom = w
	sb.border_color = c

static func apply_theme():
	var theme: Theme = load(THEME)
	if theme == null:
		return
	var o := _orig(theme)
	var s: Dictionary = data().style
	var r: int = get_value("btn_radius")
	var bw: int = get_value("btn_border_w")
	var bc: Color = get_value("btn_border")
	for st in ["normal", "hover", "pressed", "disabled"]:
		var base = o["Button/" + st]
		if not (base is StyleBoxFlat):
			continue
		var sb: StyleBoxFlat = base.duplicate()
		if st == "hover" and s.has("btn_hover"):
			sb.bg_color = get_value("btn_hover")
		elif st in ["normal", "pressed"] and s.has("btn_bg"):
			sb.bg_color = get_value("btn_bg")
		elif st == "disabled" and s.has("btn_bg"):
			sb.bg_color = Color(get_value("btn_bg")).darkened(0.45)
		if s.has("btn_radius"):
			_radius(sb, r)
		if s.has("btn_border_w") and bw > 0:
			_border(sb, bw, bc if st != "hover" else bc.lightened(0.3))
		theme.set_stylebox(st, "Button", sb)
	var focus = o["Button/focus"]
	if focus is StyleBoxFlat:
		var fs: StyleBoxFlat = focus.duplicate()
		if s.has("focus"):
			fs.border_color = get_value("focus")
		if s.has("btn_radius"):
			_radius(fs, r)
		theme.set_stylebox("focus", "Button", fs)
	var tc = get_value("btn_text") if s.has("btn_text") else null
	for c in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]:
		theme.set_color(c, "Button", tc if tc != null else o["Button/" + c])
	theme.set_color("font_color", "Label", get_value("text") if s.has("text") else o["Label/font_color"])
	theme.set_color("font_color", "LineEdit", get_value("field_text") if s.has("field_text") else o["LineEdit/font_color"])
	var fn = o["LineEdit/normal"]
	if fn is StyleBoxFlat:
		var sb2: StyleBoxFlat = fn.duplicate()
		if s.has("field_bg"):
			sb2.bg_color = get_value("field_bg")
		if s.has("btn_radius"):
			_radius(sb2, int(min(r, 12)))
		theme.set_stylebox("normal", "LineEdit", sb2)
	var ff = o["LineEdit/focus"]
	if ff is StyleBoxFlat:
		var sb3: StyleBoxFlat = ff.duplicate()
		if s.has("focus"):
			sb3.border_color = get_value("focus")
		if s.has("btn_radius"):
			_radius(sb3, int(min(r, 12)))
		theme.set_stylebox("focus", "LineEdit", sb3)

# --- the menu itself (one of these in it) ----------------------------------------

var menu: Control

func _ready():
	name = "MenuStyle"
	add_to_group("menu_style")
	menu = get_parent()
	apply_theme()
	# (after the sidebar has made its extra buttons)
	yield(get_tree(), "idle_frame")
	restyle()

func _meta_orig(n: Object, key: String, v):
	if not n.has_meta(key):
		n.set_meta(key, v)
	return n.get_meta(key)

func restyle():
	if menu == null or not is_instance_valid(menu):
		return
	var s: Dictionary = data().style
	if menu is ColorRect:
		var t0 = _meta_orig(menu, "ms_tint", menu.color)
		menu.color = get_value("menu_tint") if s.has("menu_tint") else t0
	var side = menu.get_node_or_null("Sidebar")
	if side == null:
		return
	var p = side.get_stylebox("panel")
	if p is StyleBoxFlat:
		var p0: Color = _meta_orig(p, "ms_bg", p.bg_color)
		p.bg_color = get_value("sidebar_bg") if s.has("sidebar_bg") else p0
	var done := {}
	for b in side.get_node("L").get_children():
		if not (b is Button):
			continue
		for st in ["normal", "hover", "disabled", "pressed"]:
			var sb = b.get_stylebox(st)
			if not (sb is StyleBoxFlat) or done.has(sb):
				continue
			done[sb] = true
			var c0: Color = _meta_orig(sb, "ms_bg", sb.bg_color)
			if st == "pressed":
				sb.bg_color = get_value("sidebar_sel") if s.has("sidebar_sel") else c0
			elif st == "hover" and sb != b.get_stylebox("normal"):
				sb.bg_color = Color(get_value("sidebar_sel")).lightened(0.05) if s.has("sidebar_sel") else c0
			else:
				sb.bg_color = get_value("sidebar_bg") if s.has("sidebar_bg") else c0
		var tex = b.get_node_or_null("Tex")
		if tex is CanvasItem:
			var m0: Color = _meta_orig(tex, "ms_mod", tex.self_modulate)
			tex.self_modulate = get_value("sidebar_icon") if s.has("sidebar_icon") else m0
		var lab = b.get_node_or_null("Label")
		if lab is Label:
			if s.has("sidebar_icon"):
				lab.add_color_override("font_color", get_value("sidebar_icon"))
			elif lab.has_color_override("font_color") and lab.has_meta("ms_lab"):
				lab.remove_color_override("font_color")
			lab.set_meta("ms_lab", true)
