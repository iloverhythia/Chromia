extends Control

# Sound Space Mode's main menu, like classic Sound Space's: the logo and a
# list of big pixel words (PLAY, SETTINGS, ... QUIT). It stands in for the
# sidebar while Sound Space Mode is on: every word is one of the sidebar's own
# buttons and does exactly what that button does, so nothing is added or
# missing. On the other pages a red BACK on the left comes back here.
#
# menu2.gd installs it. It shows up when the game opens (and whenever BACK is
# pressed); after a song you come back to the maps like before.

const PIXEL := "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"
const BOLD := "res://assets/font/Lato/Lato-Black.ttf"
const STAGE := Vector2(1280, 720)
const META_SEEN := "ss_hub_seen"
const HOVER_COLORS := [Color8(255, 40, 200), Color8(255, 230, 40), Color8(0, 220, 255), Color8(40, 245, 40), Color8(245, 140, 40)]
const RED := Color8(225, 55, 45)

var menu: Node
var sidebar: Control
var stage: Control
var items_box: Control
var back_btn: Control
var backdrop: ColorRect
var hub_open := false
var _on := false
var _fonts := {}
var _built_for := []
# Text is made at the screen's real size (fonts * ui_k, labels scaled back by
# 1/ui_k) so it stays sharp instead of being stretched up from 720p.
var ui_k := 1.0

static func install(menu_node: Node):
	if menu_node == null or menu_node.has_node("SSHub"):
		return
	var h = load("res://scripts/ui/menu/SSHub.gd").new()
	h.name = "SSHub"
	h.menu = menu_node
	menu_node.add_child(h)
	var main = menu_node.get_node_or_null("Main")
	if main:
		menu_node.move_child(h, main.get_index() + 1)

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	sidebar = menu.get_node_or_null("Sidebar")
	# a black backdrop behind the pages (Sound Space's menus are on black)
	backdrop = ColorRect.new()
	backdrop.name = "SSBackdrop"
	backdrop.color = Color(0, 0, 0)
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	backdrop.visible = false
	var main = menu.get_node_or_null("Main")
	if main:
		main.add_child(backdrop)
		main.move_child(backdrop, 0)
		backdrop.anchor_right = 1
		backdrop.anchor_bottom = 1
		backdrop.margin_left = -2000
		backdrop.margin_top = -2000
		backdrop.margin_right = 2000
		backdrop.margin_bottom = 2000
	stage = Control.new()
	stage.rect_size = STAGE
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	_build()
	# BACK on the left of the other pages (where the sidebar was)
	back_btn = _side_back()
	menu.call_deferred("add_child", back_btn)

func font(path: String, size: int, outline: int = 0, oc: Color = Color(0, 0, 0), sharp: bool = true) -> DynamicFont:
	var k: float = ui_k if sharp else 1.0
	var key := "%s|%d|%d|%s|%f" % [path, size, outline, oc.to_html(), k]
	if not _fonts.has(key):
		var f := DynamicFont.new()
		f.font_data = load(path)
		f.size = int(round(size * k))
		f.outline_size = int(round(outline * k))
		f.set_meta("k", k) # labels using it are scaled back by this
		f.outline_color = oc
		_fonts[key] = f
	return _fonts[key]

func label(parent: Node, text: String, f: Font, col: Color, pos: Vector2, size: Vector2, align: int = Label.ALIGN_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.add_color_override("font_outline_modulate", Color(1, 1, 1))
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	l.rect_position = pos
	var k: float = float(f.get_meta("k")) if f.has_meta("k") else 1.0
	l.rect_size = size * k
	l.rect_scale = Vector2.ONE / k
	l.align = align
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build():
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.rect_position = Vector2(-2000, -2000)
	bg.rect_size = STAGE + Vector2(4000, 4000)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(bg)
	# the logo, in Sound Space's two colours
	# the game's logo
	var logo := TextureRect.new()
	logo.texture = load("res://assets/images/branding/logo.png")
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.rect_position = Vector2(380, 18)
	logo.rect_size = Vector2(520, 176)
	logo.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(logo)
	items_box = Control.new()
	items_box.rect_position = Vector2(340, 210)
	items_box.rect_size = Vector2(600, 440)
	items_box.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(items_box)

# The sidebar's buttons, in its order (hidden ones left out, like the sidebar).
func _entries() -> Array:
	var out := []
	if sidebar == null:
		return out
	var l = sidebar.get_node_or_null("L")
	if l == null:
		return out
	for b in l.get_children():
		if not (b is BaseButton) or not b.visible:
			continue
		var t := ""
		var lab = b.get_node_or_null("Label")
		if lab is Label:
			t = lab.text
		if t == "":
			t = b.name
		if b.name == "Results":
			t = "Play"
		out.append([b, t.to_upper()])
	return out

func _rebuild_items():
	for c in items_box.get_children():
		c.queue_free()
	var es := _entries()
	_built_for = []
	for e in es:
		_built_for.append(e[0])
	var n: int = max(1, es.size())
	var gap: float = min(44.0, 420.0 / n)
	var size := int(clamp(gap * 0.62, 16, 30))
	for i in range(es.size()):
		var e: Array = es[i]
		var last: bool = i == es.size() - 1
		var f := font(PIXEL, size + (8 if last or i == 0 else 0), 3, Color(0, 0, 0))
		var w: float = f.get_string_size(e[1]).x / ui_k + 24
		var it := Item.new()
		it.hub = self
		it.hover_color = HOVER_COLORS[i % HOVER_COLORS.size()]
		it.rect_size = Vector2(w, gap)
		it.rect_position = Vector2((items_box.rect_size.x - w) / 2.0, i * gap)
		items_box.add_child(it)
		it.lab = label(it, e[1], f, Color(1, 1, 1), Vector2.ZERO, it.rect_size, Label.ALIGN_CENTER)
		it.connect("clicked", self, "_on_item", [e[0]])

func _side_back() -> Control:
	var b := Item.new()
	b.hub = self
	b.name = "SSBack"
	b.hover_color = Color8(255, 120, 110)
	b.rect_size = Vector2(220, 52)
	b.rect_pivot_offset = b.rect_size / 2
	b.rect_rotation = -90
	b.visible = false
	b.lab = label(b, "BACK", font(PIXEL, 34, 3, Color(0.35, 0.05, 0.05), false), RED, Vector2.ZERO, b.rect_size, Label.ALIGN_CENTER)
	b.base_color = RED
	b.connect("clicked", self, "open")
	return b

func open():
	hub_open = true
	_rebuild_items()

func _resharpen(k: float):
	ui_k = k
	for c in stage.get_children():
		c.queue_free()
	_build()
	_rebuild_items()

func close():
	hub_open = false

func _on_item(btn):
	close()
	if is_instance_valid(btn):
		btn.emit_signal("pressed")

func _process(_d):
	var on: bool = bool(Rhythia.get("sound_space_mode"))
	if on != _on:
		_on = on
		if on and not Engine.has_meta(META_SEEN):
			open()
		if not on:
			hub_open = false
		if sidebar:
			sidebar.visible = not on
		var sc = menu.get_node_or_null("SidebarClick")
		if sc and on:
			sc.visible = false
	if on:
		Engine.set_meta(META_SEEN, true)
	visible = on and hub_open
	backdrop.visible = on
	if visible:
		# the sidebar's buttons can change (VR found, single map mode)
		var now := []
		for e in _entries():
			now.append(e[0])
		if now != _built_for:
			_rebuild_items()
	var vp: Vector2 = get_viewport_rect().size
	var k: float = min(vp.x / STAGE.x, vp.y / STAGE.y)
	# phones stretch the whole UI to the screen: count that in too
	var stretch: float = max(0.25, min(OS.window_size.x / max(vp.x, 1.0), OS.window_size.y / max(vp.y, 1.0)))
	var want: float = k * stretch
	if visible and abs(want - ui_k) > ui_k * 0.03:
		_resharpen(want)
	stage.rect_scale = Vector2(k, k)
	stage.rect_global_position = ((vp - STAGE * k) / 2.0).floor()
	# BACK on the pages other than the maps (those have their own)
	if is_instance_valid(back_btn):
		var maps = menu.get_node_or_null("Main/Maps")
		back_btn.visible = on and not hub_open and maps != null and not maps.visible
		if back_btn.visible:
			var s: float = clamp(vp.y / 720.0, 0.6, 2.0)
			back_btn.rect_scale = Vector2(s, s)
			back_btn.rect_global_position = Vector2(30 * s - back_btn.rect_size.x / 2.0, vp.y / 2.0 - back_btn.rect_size.y / 2.0)

func _unhandled_key_input(e):
	if not _on or not e.pressed or e.echo:
		return
	if e.scancode == KEY_ESCAPE:
		var ssm = menu.get_node_or_null("Main/SSMenu")
		if ssm and ssm.visible and ssm.song_view != null:
			return # that closes the map's screen first
		if hub_open:
			# back to where you were
			close()
		else:
			open()
		get_tree().set_input_as_handled()

class Item extends Control:
	signal clicked
	var hub
	var lab: Label
	var hover_color := Color(1, 1, 1)
	var base_color := Color(1, 1, 1)
	func _init():
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_h", [true])
		connect("mouse_exited", self, "_h", [false])
	func _h(v: bool):
		if lab:
			lab.add_color_override("font_color", hover_color if v else base_color)
	func _gui_input(e):
		if e is InputEventMouseButton and e.button_index == BUTTON_LEFT:
			accept_event()
			if not e.pressed and Rect2(Vector2.ZERO, rect_size).has_point(e.position):
				emit_signal("clicked")
