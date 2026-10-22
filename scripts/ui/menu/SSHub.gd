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
var _closing := false
var _last_page = null
const Sfx = preload("res://scripts/ui/menu/SSSfx.gd")
const Cam = preload("res://scripts/ui/menu/SSCam.gd")
const WHIP_TIME := 0.28
# the camera (scripts/ui/menu/SSCam.gd): sway follows the cursor and is shared
# with the map screen and the pages; whip is this menu's turn away / back
var cam: Node2D
var sway := Vector2.ZERO
var whip := 0.0
var page_whip := 0.0
var entry_whip := -1.0 # where the next screen comes in from
var _main_base = null  # Main's margins before the pages were moved

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
	# the menu hangs under a "camera" node that leans and turns it
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
		# the camera turns back to the menu: from the maps (on its left) it
		# comes in from the right, from a page (on its right) from the left
		var maps = menu.get_node_or_null("Main/Maps")
		var from_maps: bool = maps != null and maps.visible
		_whip_in(1.0 if from_maps else -1.0)

func _whip_in(from: float):
	Sfx.play(self, "swoosh")
	whip = from
	var tw := create_tween()
	tw.tween_property(self, "whip", 0.0, WHIP_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _on_back_btn():
	Sfx.play(self, "select")
	open()

func _tick():
	Sfx.play(self, "tick")

func _resharpen(k: float):
	ui_k = k
	for c in stage.get_children():
		c.queue_free()
	_build()
	_rebuild_items()

# to_maps: PLAY (the maps are to the menu's left, so the menu is thrown to
# the right and the maps come in from the left); anything else the other way
func close(to_maps: bool = false):
	if not hub_open:
		return
	hub_open = false
	_closing = true
	entry_whip = -1.0 if to_maps else 1.0
	var ssm = menu.get_node_or_null("Main/SSMenu")
	var maps = menu.get_node_or_null("Main/Maps")
	if to_maps and ssm and maps and maps.visible:
		ssm.call_deferred("_whip_in") # the maps were already up under the menu
	var tw := create_tween()
	tw.tween_property(self, "whip", 1.0 if to_maps else -1.0, WHIP_TIME * 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_callback(self, "_closed")

func _closed():
	_closing = false
	whip = 0.0

# the screen that comes up next asks where to come in from
func take_entry_whip() -> float:
	var w := entry_whip
	entry_whip = -1.0
	return w

func _on_item(btn):
	Sfx.play(self, "select")
	close(is_instance_valid(btn) and btn.name == "Results")
	if is_instance_valid(btn):
		btn.emit_signal("pressed")

func _process(delta):
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
	var want: float = k * stretch
	if visible and abs(want - ui_k) > ui_k * 0.03:
		_resharpen(want)
	stage.rect_scale = Vector2(k, k)
	stage.rect_position = ((vp - STAGE * k) / 2.0).floor()
	# the camera drifts toward the cursor / finger, smoothly
	var m: Vector2 = get_viewport().get_mouse_position()
	var target := Vector2(clamp((m.x - vp.x / 2.0) / (vp.x / 2.0), -1.0, 1.0), clamp((m.y - vp.y / 2.0) / (vp.y / 2.0), -1.0, 1.0))
	sway = sway.linear_interpolate(target, 1.0 - exp(-delta * 3.0))
	cam.visible = visible
	cam.transform = Cam.xform(vp, sway, whip)
	_move_pages(on, vp)
	# BACK on the pages other than the maps (those have their own)
	if is_instance_valid(back_btn):
		var maps = menu.get_node_or_null("Main/Maps")
		back_btn.visible = on and not hub_open and maps != null and not maps.visible
		_page_anim(on)
		if back_btn.visible:
			var s: float = clamp(vp.y / 720.0, 0.6, 2.0)
			back_btn.rect_scale = Vector2(s, s)
			back_btn.rect_global_position = Vector2(30 * s - back_btn.rect_size.x / 2.0, vp.y / 2.0 - back_btn.rect_size.y / 2.0)

# A page that comes up is turned to like Sound Space's camera turning to
# another panel: it whips in from the side, then drifts with the cursor.
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
	page_whip = take_entry_whip() if entry_whip != -1.0 else 1.0
	var tw := create_tween()
	tw.tween_property(self, "page_whip", 0.0, WHIP_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# The pages (settings, profile...) can only be moved, not leaned: they drift
# with the cursor and whip in sideways. Put back when Sound Space Mode is off.
func _move_pages(on: bool, vp: Vector2):
	var main = menu.get_node_or_null("Main")
	if main == null:
		return
	if not on:
		if _main_base != null:
			main.margin_left = _main_base[0]
			main.margin_right = _main_base[1]
			main.margin_top = _main_base[2]
			main.margin_bottom = _main_base[3]
			_main_base = null
		return
	if _main_base == null:
		_main_base = [main.margin_left, main.margin_right, main.margin_top, main.margin_bottom]
	var d: Vector2 = Cam.shift(vp, sway, page_whip)
	var sc: Vector2 = main.get_global_transform().get_scale()
	d /= Vector2(max(sc.x, 0.001), max(sc.y, 0.001))
	main.margin_left = _main_base[0] + d.x
	main.margin_right = _main_base[1] + d.x
	main.margin_top = _main_base[2] + d.y
	main.margin_bottom = _main_base[3] + d.y

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
