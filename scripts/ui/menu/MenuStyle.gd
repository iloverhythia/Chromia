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
	"accent": Color(1, 0.756863, 0.960784),
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

# Every control type in the theme (buttons, dropdowns, preset buttons, tabs,
# lists, popups...) and every control with its own colours set in the menu's
# scenes or code follows the look: the menu's own colours are swapped for
# yours wherever they're used (PALETTE: the button lilac, its hover, the text
# box grey, the pink headings, the label text...), and buttons of every kind
# get your roundness and border.

const BUTTON_TYPES := ["Button", "MenuButton", "OptionButton", "ToolButton", "ColorPickerButton", "CheckButton", "CheckBox", "LinkButton"]
const BTN_FONT := ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]
# backgrounds: the menu's colour -> [key, lighter (+) / darker (-)]
const PALETTE_BG := [
	[Color(0.764706, 0.65098, 0.8), "btn_bg", 0.0],
	[Color(0.913725, 0.74902, 0.94902), "btn_hover", 0.0],
	[Color(0.470588, 0.305882, 0.521569), "btn_bg", -0.35],
	[Color(0.317647, 0.227451, 0.345098), "btn_bg", -0.55],
	[Color(0.858824, 0.286275, 0.980392), "btn_hover", -0.2],
	[Color(0.639216, 0.576471, 0.658824), "field_bg", 0.0],
	[Color(1, 0.756863, 0.960784), "accent", 0.0],
]
# text: the menu's colour -> [key, lighter / darker]
const PALETTE_TEXT := [
	[Color(0.898039, 0.94902, 1), "text", 0.0],
	[Color(1, 1, 1), "text", 0.0],
	[Color(0.690196, 0.690196, 0.690196), "text", -0.25],
	[Color(1, 0.756863, 0.960784), "accent", 0.0],
	[Color(0.913725, 0.74902, 0.94902), "accent", 0.1],
]

static func _near(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.02 and abs(a.g - b.g) < 0.02 and abs(a.b - b.b) < 0.02

static func _shade(c: Color, k: float) -> Color:
	return c.lightened(k) if k > 0.0 else (c.darkened(-k) if k < 0.0 else c)

static func _from(pal: Array, c: Color):
	var s: Dictionary = data().style
	for p in pal:
		if _near(c, p[0]):
			if not s.has(p[1]):
				return null
			var v: Color = _shade(get_value(p[1]), float(p[2]))
			v.a = c.a * v.a
			return v
	return null

# a background colour as it is with your look (or as it was)
static func bg_color(c: Color) -> Color:
	var v = _from(PALETTE_BG, c)
	return v if v != null else c

static func is_button_color(c: Color) -> bool:
	for i in 5:
		if _near(c, PALETTE_BG[i][0]):
			return true
	return false

# a text colour: on a button, the button's black text becomes yours
static func text_color(c: Color, on_button: bool) -> Color:
	var s: Dictionary = data().style
	if on_button and _near(c, Color(0, 0, 0)) and s.has("btn_text"):
		var t: Color = get_value("btn_text")
		t.a = c.a
		return t
	var v = _from(PALETTE_TEXT, c)
	return v if v != null else c

# a stylebox made from the original with your look
static func styled(orig: StyleBoxFlat, button: bool, style_name: String) -> StyleBoxFlat:
	var s: Dictionary = data().style
	var sb: StyleBoxFlat = orig.duplicate()
	var btn: bool = button and is_button_color(orig.bg_color)
	if btn and style_name == "disabled" and s.has("btn_bg"):
		sb.bg_color = Color(get_value("btn_bg")).darkened(0.45)
	else:
		sb.bg_color = bg_color(orig.bg_color)
	if style_name == "focus" and s.has("focus"):
		sb.border_color = get_value("focus")
	else:
		sb.border_color = bg_color(orig.border_color)
	if (btn or (button and style_name == "focus")) and s.has("btn_radius"):
		_radius(sb, int(get_value("btn_radius")))
	if btn and s.has("btn_border_w") and int(get_value("btn_border_w")) > 0:
		var bc: Color = get_value("btn_border")
		_border(sb, int(get_value("btn_border_w")), bc if style_name != "hover" else bc.lightened(0.3))
	return sb

static func _orig(theme: Theme) -> Dictionary:
	if theme.has_meta("menu_style_orig2"):
		return theme.get_meta("menu_style_orig2")
	var o := {}
	for type in theme.get_type_list(""):
		for n in theme.get_stylebox_list(type):
			var sb = theme.get_stylebox(n, type)
			if sb is StyleBoxFlat:
				o["%s/sb/%s" % [type, n]] = sb.duplicate()
		for n in theme.get_color_list(type):
			o["%s/c/%s" % [type, n]] = theme.get_color(n, type)
	theme.set_meta("menu_style_orig2", o)
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
	# Each change to the theme makes every control in the menu redo its look
	# and layout: all ~240 at once flooded the engine's message queue and the
	# menu took seconds to open (black screen). So: nothing when the look on
	# the theme is already this one (never anything without a look of your
	# own), and the changes made quietly, the menu told once at the end.
	var sig := to_json(s)
	if String(theme.get_meta("menu_style_applied") if theme.has_meta("menu_style_applied") else "{}") == sig:
		return
	theme.set_meta("menu_style_applied", sig)
	theme.set_block_signals(true)
	for key in o:
		var parts: Array = key.split("/")
		var type: String = parts[0]
		var what: String = parts[1]
		var n: String = parts[2]
		var button: bool = BUTTON_TYPES.has(type)
		if what == "sb":
			var sb := styled(o[key], button, n)
			if type == "LineEdit" or type == "TextEdit" or type == "SpinBox":
				if s.has("field_bg") and n in ["normal", "read_only"]:
					sb.bg_color = get_value("field_bg")
				if s.has("focus") and n == "focus":
					sb.border_color = get_value("focus")
				if s.has("btn_radius"):
					_radius(sb, int(min(int(get_value("btn_radius")), 12)))
			theme.set_stylebox(n, type, sb)
		else:
			var c0: Color = o[key]
			var c := text_color(c0, button)
			if button and BTN_FONT.has(n) and s.has("btn_text"):
				c = get_value("btn_text")
			elif type == "Label" and n == "font_color" and s.has("text"):
				c = get_value("text")
			elif (type == "LineEdit" or type == "TextEdit") and n == "font_color" and s.has("field_text"):
				c = get_value("field_text")
			theme.set_color(n, type, c)
	theme.set_block_signals(false)
	theme.emit_changed()

# --- controls with their own colours (set in a scene or by code) -----------------

const SB_NAMES := ["normal", "hover", "pressed", "disabled", "focus", "panel", "bg", "fg", "tab_fg", "tab_bg", "read_only", "grabber_area", "slider"]
const COLOR_NAMES := ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus", "font_color_disabled"]

# (each override's original is kept with the one put on, so a control that
# changes its own colours later, e.g. a selected tab, is followed too)
static func restyle_control(c: Control):
	var active: bool = not data().style.empty()
	var button: bool = c is BaseButton
	for n in SB_NAMES:
		if not c.has_stylebox_override(n):
			continue
		var mk: String = "ms_sb_" + n
		var cur = c.get_stylebox(n)
		var o = null
		if c.has_meta(mk) and c.get_meta(mk)[1] == cur:
			o = c.get_meta(mk)[0]
		elif cur is StyleBoxFlat and active and (is_button_color(cur.bg_color) or bg_color(cur.bg_color) != cur.bg_color or bg_color(cur.border_color) != cur.border_color):
			# (only the ones in the menu's colours: everything else keeps its own look)
			o = cur
		if o == null:
			if c.has_meta(mk):
				c.remove_meta(mk)
			continue
		var sb := styled(o, button, n)
		c.add_stylebox_override(n, sb)
		c.set_meta(mk, [o, sb])
	for n in COLOR_NAMES:
		if not c.has_color_override(n):
			continue
		var mk2: String = "ms_c_" + n
		var cur2: Color = c.get_color(n)
		var o2 = null
		if c.has_meta(mk2) and c.get_meta(mk2)[1] == cur2:
			o2 = c.get_meta(mk2)[0]
		elif active and text_color(cur2, button) != cur2:
			o2 = cur2
		if o2 == null:
			if c.has_meta(mk2):
				c.remove_meta(mk2)
			continue
		var v := text_color(o2, button)
		c.add_color_override(n, v)
		c.set_meta(mk2, [o2, v])

static func restyle_tree(n: Node):
	if n is Control:
		restyle_control(n)
	for ch in n.get_children():
		restyle_tree(ch)

# --- the menu itself (one of these in it) ----------------------------------------

var menu: Control

var _pending := []

func _enter_tree():
	if not get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().connect("node_added", self, "_on_node_added")

func _exit_tree():
	if get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().disconnect("node_added", self, "_on_node_added")

# controls made while the menu is open (pages, lists, popups) follow the look
# too: looked at once, after they've set their own colours
func _on_node_added(n: Node):
	if not (n is Control) or data().style.empty():
		return
	if _pending.empty():
		call_deferred("_restyle_pending")
	_pending.append(n)

func _restyle_pending():
	var list := _pending
	_pending = []
	for n in list:
		if is_instance_valid(n) and n.is_inside_tree():
			restyle_control(n)

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
	restyle_tree(get_tree().root)
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
