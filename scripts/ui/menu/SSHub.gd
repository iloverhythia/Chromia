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
var logo: TextureRect
var _last_page = null
const Sfx = preload("res://scripts/ui/menu/SSSfx.gd")
var cam: Node2D # holds the menu, drawn at the window's size over everything

# Switching menus, like Sound Space's camera turning from one panel to the
# next: the screen you leave slides off to one side, leaning and fading, and
# the new one slides in from the other side and settles. Going into something
# comes in from the right, BACK from the left. t: 0 = in place, -1 / +1 = off
# to the left / right.
const IN_TIME := 0.34
const OUT_TIME := 0.24
var t_hub := 0.0
var t_page := 0.0
var _closing := false
var _page_from := 1.0
var _main_base = null # the pages' margins / look before moving them

static func screen_xf(vp: Vector2, t: float) -> Transform2D:
	var c := vp / 2.0
	var x_axis := Vector2(1.0 - abs(t) * 0.1, t * 0.16) # squeezed and leaning while off to the side
	var y_axis := Vector2(0, 1)
	return Transform2D(x_axis, y_axis, c + Vector2(t * vp.x * 0.35, 0) - (x_axis * c.x + y_axis * c.y))

func _slide(prop: String, from: float, to: float, time: float, ease_in: bool):
	set(prop, from)
	var tw := create_tween()
	# leaving: off fast so the new screen shows; coming in: settles softly
	tw.tween_property(self, prop, to, time).set_trans(Tween.TRANS_CUBIC if ease_in else Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return tw

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
	cam = Node2D.new()
	cam.set_as_toplevel(true)
	add_child(cam)
	stage = Control.new()
	stage.rect_size = STAGE
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	cam.add_child(stage)
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
	logo = TextureRect.new()
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
	b.connect("clicked", self, "_on_back_btn")
	return b

func open():
	var was := hub_open
	hub_open = true
	_closing = false
	_rebuild_items()
	if not was:
		Sfx.play(self, "swoosh")
		# back to the menu: it comes in from the left, what you were on goes right
		_slide("t_hub", -1.0, 0.0, IN_TIME, false)
		var maps = menu.get_node_or_null("Main/Maps")
		var ssm = menu.get_node_or_null("Main/SSMenu")
		if maps and maps.visible and ssm:
			ssm.slide(0.0, 1.0, OUT_TIME, true)
		elif _last_page != null:
			_slide("t_page", 0.0, 1.0, OUT_TIME, true)

func _on_back_btn():
	Sfx.play(self, "select")
	open()

func _resharpen(k: float):
	ui_k = k
	for c in stage.get_children():
		c.queue_free()
	_build()
	_rebuild_items()

func close(to_maps: bool = false):
	if not hub_open:
		return
	hub_open = false
	# the menu goes off to the left, what you picked comes in from the right
	_closing = true
	_slide("t_hub", 0.0, -1.0, OUT_TIME, true).tween_callback(self, "_closed")
	_page_from = 1.0
	var maps = menu.get_node_or_null("Main/Maps")
	var ssm = menu.get_node_or_null("Main/SSMenu")
	if to_maps and maps and maps.visible and ssm:
		ssm.slide(1.0, 0.0, IN_TIME, false) # the maps were already up under the menu
	elif not to_maps:
		_last_page = null # whatever page shows next slides in

func _closed():
	_closing = false
	t_hub = 0.0

func _on_item(btn):
	Sfx.play(self, "select")
	close(is_instance_valid(btn) and btn.name == "Results")
	if is_instance_valid(btn):
		btn.emit_signal("pressed")

func _process(_delta):
	var on: bool = bool(Rhythia.call("ss_menus_on"))
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
	visible = on and (hub_open or _closing)
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
	if get_viewport() != get_tree().root:
		stretch = 1.0 # VR: drawn on the menu screen's own viewport, not the window
	var want: float = k * stretch
	if visible and abs(want - ui_k) > ui_k * 0.03:
		_resharpen(want)
	stage.rect_scale = Vector2(k, k)
	stage.rect_position = ((vp - STAGE * k) / 2.0).floor()
	cam.visible = visible
	cam.transform = screen_xf(vp, t_hub)
	stage.modulate.a = 1.0 - abs(t_hub)
	_place_pages(on, vp)
	# BACK on the pages other than the maps (those have their own)
	if is_instance_valid(back_btn):
		var maps = menu.get_node_or_null("Main/Maps")
		back_btn.visible = on and not hub_open and maps != null and not maps.visible
		_page_anim(on)
		if back_btn.visible:
			var s: float = clamp(vp.y / 720.0, 0.6, 2.0)
			back_btn.rect_scale = Vector2(s, s)
			back_btn.rect_global_position = Vector2(30 * s - back_btn.rect_size.x / 2.0, vp.y / 2.0 - back_btn.rect_size.y / 2.0)

# A page that comes up plays the swoosh.
func _page_anim(on: bool):
	var main = menu.get_node_or_null("Main")
	if main == null:
		return
	var cur = null
	for p in main.get_children():
		if p is Control and p.visible and p != backdrop and p.name != "SSMenu" and p.name in _page_names():
			cur = p
			break
	if cur == _last_page:
		return
	_last_page = cur
	if not on or cur == null or cur.name == "Maps":
		return
	Sfx.play(self, "swoosh")
	_slide("t_page", _page_from, 0.0, IN_TIME, false)
	_page_from = 1.0

# The pages (settings, profile...) slide and fade (they can't lean); they're
# put back exactly when they're in place or Sound Space Mode is off.
func _place_pages(on: bool, vp: Vector2):
	var main = menu.get_node_or_null("Main")
	if main == null:
		return
	if not on or is_zero_approx(t_page):
		if _main_base != null:
			main.margin_left = _main_base[0]
			main.margin_right = _main_base[1]
			main.modulate.a = _main_base[2]
			_main_base = null
		return
	if _main_base == null:
		_main_base = [main.margin_left, main.margin_right, main.modulate.a]
	var sc: float = max(main.get_global_transform().get_scale().x, 0.001)
	var dx: float = t_page * vp.x * 0.35 / sc
	main.margin_left = _main_base[0] + dx
	main.margin_right = _main_base[1] + dx
	main.modulate.a = _main_base[2] * (1.0 - abs(t_page))

func _page_names() -> Array:
	var out := []
	if sidebar and "pages" in sidebar:
		for p in sidebar.pages:
			if is_instance_valid(p):
				out.append(p.name)
	return out

func _unhandled_key_input(e):
	if not _on or not e.pressed or e.echo:
		return
	if e.scancode == KEY_ESCAPE:
		var ssm = menu.get_node_or_null("Main/SSMenu")
		if ssm and ssm.visible and ssm.song_view != null:
			return # that closes the map's screen first
		if hub_open:
			# back to where you were
			var mp = menu.get_node_or_null("Main/Maps")
			close(mp != null and mp.visible)
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
		if v:
			load("res://scripts/ui/menu/SSSfx.gd").play(self, "tick")
	func _gui_input(e):
		if e is InputEventMouseButton and e.button_index == BUTTON_LEFT:
			accept_event()
			if not e.pressed and Rect2(Vector2.ZERO, rect_size).has_point(e.position):
				emit_signal("clicked")
