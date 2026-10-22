extends Node

# Sound Space Mode's look for the menu pages (settings, profile, online, map
# browser, content, credits, update log...): black with neon outlines, like
# classic Sound Space's menus. Panels get a coloured frame, buttons are black
# with a coloured outline and coloured text (the colours go round Sound
# Space's set), text boxes get Sound Space's red value box, and big titles
# use the pixel font. Only how things look changes: every control stays where
# it is and does what it did. Everything is put back when Sound Space Mode is
# turned off. Things a page adds later (lists that load in) are styled too.
#
# menu2.gd installs it. The maps page has its own Sound Space screen
# (SSMenu.gd); the map editor keeps its own look.

const PIXEL := "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"
const BOLD := "res://assets/font/Lato/Lato-Black.ttf"
const JP := "res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"
const SKIP_PAGES := ["Maps", "MapEditor", "SSMenu", "SSBackdrop"]

const CYAN := Color8(0, 220, 255)
const MAGENTA := Color8(255, 40, 200)
const YELLOW := Color8(255, 220, 40)
const GREEN := Color8(40, 245, 40)
const RED := Color8(235, 55, 45)
const ORANGE := Color8(245, 140, 40)
const PALETTE := [CYAN, MAGENTA, YELLOW, GREEN, RED, ORANGE]
# each page's main colour, like Sound Space's (stats magenta, profiles red...)
const ACCENTS := {
	"Settings": RED, "Stats": MAGENTA, "Profile": RED, "Online": CYAN,
	"Content": GREEN, "Credits": YELLOW, "UpdateLog": ORANGE, "Language": GREEN,
	"MapBrowser": CYAN,
}

# overrides this changes, per kind of control
const BUTTON_PROPS := ["custom_styles/normal", "custom_styles/hover", "custom_styles/pressed", "custom_styles/focus", "custom_styles/disabled", "custom_fonts/font", "custom_colors/font_color", "custom_colors/font_color_hover", "custom_colors/font_color_pressed", "custom_colors/font_color_focus"]
const CHECK_PROPS := ["custom_fonts/font", "custom_colors/font_color", "custom_colors/font_color_hover", "custom_colors/font_color_pressed", "custom_colors/font_color_hover_pressed", "custom_colors/font_color_focus", "custom_styles/normal", "custom_styles/hover", "custom_styles/pressed", "custom_styles/focus"]
const LABEL_PROPS := ["custom_fonts/font", "custom_colors/font_color", "custom_colors/font_outline_modulate", "custom_colors/font_color_shadow"]
const EDIT_PROPS := ["custom_styles/normal", "custom_styles/focus", "custom_styles/read_only", "custom_fonts/font", "custom_colors/font_color"]
const TABS_PROPS := ["custom_styles/tab_fg", "custom_styles/tab_bg", "custom_styles/panel", "custom_fonts/font", "custom_colors/font_color_fg", "custom_colors/font_color_bg"]
const PANEL_PROPS := ["custom_styles/panel"]
const SLIDER_PROPS := ["custom_styles/slider", "custom_styles/grabber_area", "custom_styles/grabber_area_highlight"]
const PROGRESS_PROPS := ["custom_styles/fg", "custom_styles/bg"]
const LIST_PROPS := ["custom_fonts/font", "custom_styles/bg"]

var menu: Node
var _on := false
var _saved := {}   # node -> {property: old value}
var _fonts := {}
var _turn := 0     # which palette colour the next button gets

static func install(menu_node: Node):
	if menu_node == null or menu_node.has_node("SSSkin"):
		return
	var s = load("res://scripts/ui/menu/SSSkin.gd").new()
	s.name = "SSSkin"
	s.menu = menu_node
	menu_node.add_child(s)

func _ready():
	get_tree().connect("node_added", self, "_on_node_added")

func _process(_d):
	var want: bool = bool(Rhythia.get("sound_space_mode"))
	if want == _on:
		return
	_on = want
	if want:
		_apply_all()
	else:
		_restore_all()

func _pages() -> Array:
	var out := []
	var main = menu.get_node_or_null("Main")
	if main == null:
		return out
	for p in main.get_children():
		if p is Control and not p.name in SKIP_PAGES:
			out.append(p)
	return out

func _page_of(n: Node) -> Node:
	var main = menu.get_node_or_null("Main")
	var cur := n
	while cur != null and cur.get_parent() != main:
		cur = cur.get_parent()
	return cur

func _accent(page: Node) -> Color:
	return ACCENTS.get(page.name, CYAN) if page else CYAN

func _apply_all():
	for p in _pages():
		_turn = 0
		_walk(p, _accent(p))

func _walk(n: Node, accent: Color):
	if n is Control:
		_style(n, accent)
	for c in n.get_children():
		_walk(c, accent)

func _on_node_added(n: Node):
	if not _on or not (n is Control) or menu == null or not is_instance_valid(menu):
		return
	var page = _page_of(n)
	if page == null or not (page is Control) or page.name in SKIP_PAGES:
		return
	# after the node's own script has set it up
	call_deferred("_style_late", n, _accent(page))

func _style_late(n, accent: Color):
	if _on and is_instance_valid(n) and n.is_inside_tree():
		_walk(n, accent)

func _restore_all():
	for n in _saved:
		if not is_instance_valid(n):
			continue
		var d: Dictionary = _saved[n]
		for prop in d:
			n.set(prop, d[prop])
	_saved.clear()

func _save(n: Control, props: Array):
	var d := {}
	for p in props:
		d[p] = n.get(p)
	_saved[n] = d

# --- looks --------------------------------------------------------------------

func font(path: String, size: int, outline: int = 0) -> DynamicFont:
	var key := "%s|%d|%d" % [path, size, outline]
	if not _fonts.has(key):
		var f := DynamicFont.new()
		f.font_data = load(path)
		f.size = size
		f.outline_size = outline
		f.outline_color = Color(0, 0, 0)
		var jp = load(JP)
		if jp and path != JP:
			f.add_fallback(jp)
		_fonts[key] = f
	return _fonts[key]

static func box(fill: Color, border: Color, width: int, radius: int, pad_x: float = 8.0, pad_y: float = 4.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s

func _size_of(n: Control, fallback: int = 18) -> int:
	var f = n.get_font("font")
	if f is DynamicFont:
		return f.size
	if f is BitmapFont:
		return int(f.get_height() * 0.8)
	return fallback

func _style(n: Control, accent: Color):
	if _saved.has(n) or n.has_meta("ss_skip"):
		return
	if n is CheckBox or n is CheckButton:
		_save(n, CHECK_PROPS)
		var size := _size_of(n)
		n.add_font_override("font", font(BOLD, size, 1))
		for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
			n.add_color_override(k, Color(1, 1, 1) if k != "font_color_hover" else accent.lightened(0.3))
		var clear := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 4, 2)
		for k in ["normal", "hover", "pressed", "focus"]:
			n.add_stylebox_override(k, clear)
	elif n is Button:
		if n.get_parent() and n.get_parent().name == "L" and n.get_parent().get_parent() == menu.get_node_or_null("Sidebar"):
			return
		_save(n, BUTTON_PROPS)
		var col: Color = PALETTE[_turn % PALETTE.size()]
		_turn += 1
		var r := 10
		n.add_stylebox_override("normal", box(Color(0, 0, 0, 0.85), col, 3, r))
		n.add_stylebox_override("hover", box(col.darkened(0.7), col.lightened(0.2), 3, r))
		n.add_stylebox_override("pressed", box(col.darkened(0.5), Color(1, 1, 1), 3, r))
		n.add_stylebox_override("focus", box(Color(0, 0, 0, 0), col.lightened(0.4), 2, r))
		n.add_stylebox_override("disabled", box(Color(0, 0, 0, 0.6), col.darkened(0.6), 3, r))
		n.add_font_override("font", font(BOLD, _size_of(n), 1))
		n.add_color_override("font_color", col)
		n.add_color_override("font_color_hover", col.lightened(0.35))
		n.add_color_override("font_color_pressed", Color(1, 1, 1))
		n.add_color_override("font_color_focus", col)
	elif n is LineEdit:
		_save(n, EDIT_PROPS)
		n.add_stylebox_override("normal", box(Color(0, 0, 0, 0.85), RED, 3, 4))
		n.add_stylebox_override("focus", box(Color(0, 0, 0, 0.9), RED.lightened(0.3), 3, 4))
		n.add_stylebox_override("read_only", box(Color(0, 0, 0, 0.6), RED.darkened(0.4), 3, 4))
		n.add_font_override("font", font(BOLD, _size_of(n), 0))
		n.add_color_override("font_color", RED.lightened(0.25))
	elif n is TabContainer:
		_save(n, TABS_PROPS)
		n.add_stylebox_override("tab_fg", box(accent.darkened(0.55), accent, 3, 8, 12, 4))
		n.add_stylebox_override("tab_bg", box(Color(0, 0, 0, 0.85), accent.darkened(0.45), 2, 8, 12, 4))
		n.add_stylebox_override("panel", box(Color(0, 0, 0, 0.8), accent, 4, 6, 8, 8))
		n.add_font_override("font", font(BOLD, _size_of(n), 1))
		n.add_color_override("font_color_fg", Color(1, 1, 1))
		n.add_color_override("font_color_bg", accent.lightened(0.2))
	elif n is PanelContainer or n is Panel:
		_save(n, PANEL_PROPS)
		n.add_stylebox_override("panel", box(Color(0, 0, 0, 0.82), accent, 4, 6))
	elif n is Label:
		_save(n, LABEL_PROPS)
		var size := _size_of(n)
		if size >= 30:
			# titles: Sound Space's pixel font in the page's colour
			n.add_font_override("font", font(PIXEL, int(size * 0.8), 3))
			n.add_color_override("font_color", accent)
		else:
			n.add_font_override("font", font(BOLD, size, 1))
		n.add_color_override("font_outline_modulate", Color(1, 1, 1))
		n.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	elif n is HSlider or n is VSlider:
		_save(n, SLIDER_PROPS)
		var line := box(Color(0.15, 0.15, 0.15), Color(0.15, 0.15, 0.15), 0, 3, 0, 3)
		n.add_stylebox_override("slider", line)
		n.add_stylebox_override("grabber_area", box(accent, accent, 0, 3, 0, 3))
		n.add_stylebox_override("grabber_area_highlight", box(accent.lightened(0.3), accent.lightened(0.3), 0, 3, 0, 3))
	elif n is ProgressBar:
		_save(n, PROGRESS_PROPS)
		n.add_stylebox_override("fg", box(GREEN, GREEN, 0, 3, 0, 0))
		n.add_stylebox_override("bg", box(Color(0, 0, 0, 0.8), Color8(40, 40, 40), 2, 3, 0, 0))
	elif n is ItemList:
		_save(n, LIST_PROPS)
		n.add_font_override("font", font(BOLD, _size_of(n), 0))
		n.add_stylebox_override("bg", box(Color(0, 0, 0, 0.82), accent, 3, 6))
