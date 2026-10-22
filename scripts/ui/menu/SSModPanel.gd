extends Control

# The song screen's modifiers as Sound Space style tiles (like its modifier
# panel): rounded tiles with an icon and a name in a magenta frame, pages
# with arrows and a "1/2" counter. Each tile stands for one of the existing
# modifier checkboxes / speed buttons (now hidden), which keep doing the work:
# a tap flips that button, and the tile lights up while it's on.
#
# menu2.gd builds it (SSModPanel.install) after the modifiers are set up.
# It only shows while Sound Space Mode is on; with it off the normal
# modifier checkboxes and speed buttons are back where they were.

const MAGENTA := Color(1.0, 0.0, 0.95)
const PAGE_GREEN := Color(0.1, 0.95, 0.2)
const ARROW_CYAN := Color(0.0, 0.85, 1.0)
const TILE_GAP := 6.0
const FRAME_W := 4.0
const PAD := 10.0
const TOP := 30.0 # room for the page counter

# [tile name, node under Mods, icon, color]
const TILES := [
	["No-Fail", "NoFail", "nofail", Color(0.35, 0.85, 0.45)],
	["Ghost", "Ghost", "ghost", Color(0.78, 0.78, 0.8)],
	["Sudden Death", "SuddenDeath", "sudden", Color(0.95, 0.35, 0.35)],
	["Extra Energy", "EasyMode", "heart", Color(0.35, 0.85, 0.6)],
	["Speed-", "SpeedMod/C/M", "minus1", Color(0.72, 0.45, 0.85)],
	["Speed+", "SpeedMod/C/P", "plus1", Color(0.2, 0.8, 0.95)],
	["Speed--", "SpeedMod/C/MM", "minus2", Color(0.72, 0.45, 0.85)],
	["Speed++", "SpeedMod/C/PP", "plus2", Color(0.45, 0.6, 0.95)],
	["Speed---", "SpeedMod/C/MMM", "minus3", Color(0.72, 0.45, 0.85)],
	["Speed+++", "SpeedMod/C/PPP", "plus3", Color(0.45, 0.6, 0.95)],
	["Speed----", "SpeedMod/C/MMMM", "minus4", Color(0.72, 0.45, 0.85)],
	["Speed++++", "SpeedMod/C/PPPP", "plus4", Color(0.45, 0.6, 0.95)],
	["No Regen", "HardMode", "noregen", Color(0.95, 0.6, 0.3)],
	["Hard Mode", "HardModeMod", "hard", Color(0.9, 0.55, 0.3)],
	["Hard Rock", "HardRock", "bolt", Color(0.95, 0.4, 0.25)],
	["Strobe", "Strobe", "strobe", Color(0.85, 0.78, 0.3)],
	["Mirror X", "MirrorX", "mirrorx", Color(0.4, 0.6, 1.0)],
	["Mirror Y", "MirrorY", "mirrory", Color(0.4, 0.6, 1.0)],
	["Earthquake", "Earthquake", "quake", Color(0.8, 0.6, 0.4)],
	["Chaos", "Chaos", "chaos", Color(1.0, 0.45, 0.75)],
	["Visual Mode", "VisualMode", "eye", Color(0.3, 0.9, 0.9)],
	["Invert Mouse", "InvertMouse", "invert", Color(0.7, 0.5, 1.0)],
	["360", "360", "spin", Color(0.3, 0.85, 0.75)],
	["Flashlight", "FlashlightMod", "light", Color(0.95, 0.9, 0.45)],
]

var mods: Control
var cols := 4
var rows := 3
var standalone := false # a second copy (Sound Space song screen): only tiles, nothing moved or hidden
var fixed_width := 0.0
var tiles := []
var page := 0
var pages := 1
var page_label: Label
var prev_btn: Button
var next_btn: Button
var _pixel: DynamicFontData
var _normal_state := {}
var _ss_state := {}
var _on = null
var _label_font: DynamicFont

# Replaces the modifier rows under Mods with the panel.
static func install(mods_node: Control):
	if mods_node == null or mods_node.has_node("SSModPanel"):
		return
	var p = load("res://scripts/ui/menu/SSModPanel.gd").new()
	p.name = "SSModPanel"
	p.mods = mods_node
	mods_node.add_child(p)
	p._build()

# A copy of the tiles for another screen: they flip the same buttons under
# mods_node, which stay where they are.
static func make_standalone(mods_node: Control, n_cols: int, n_rows: int, width: float) -> Control:
	var p = load("res://scripts/ui/menu/SSModPanel.gd").new()
	p.mods = mods_node
	p.cols = n_cols
	p.rows = n_rows
	p.standalone = true
	p.fixed_width = width
	p._build()
	return p

func _build():
	_pixel = load("res://assets/font/PressStart2P/PressStart2P-Regular.ttf")
	_label_font = DynamicFont.new()
	_label_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_label_font.size = 11
	if not standalone:
		_normal_state = _snapshot()
	var speed: Control = mods.get_node_or_null("SpeedMod")
	var width: float = fixed_width if fixed_width > 0 else (mods.rect_size.x if mods.rect_size.x > 0 else 334.0)
	# where the speed row and the checkboxes were
	var top_y: float = 0.0 if standalone else (speed.rect_position.y if speed else 60.0)
	var arrows := 24.0
	var inner_w := width - arrows * 2 - FRAME_W * 2 - PAD * 2
	var tile := floor((inner_w - TILE_GAP * (cols - 1)) / cols)
	if standalone:
		_label_font.size = int(clamp(tile * 0.13, 11, 20))
	var frame_h := TOP + rows * tile + (rows - 1) * TILE_GAP + PAD + FRAME_W * 2
	rect_position = Vector2(0, top_y)
	rect_size = Vector2(width, frame_h)
	mouse_filter = MOUSE_FILTER_PASS

	var frame := Frame.new()
	frame.rect_position = Vector2(arrows, 0)
	frame.rect_size = Vector2(width - arrows * 2, frame_h)
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(frame)

	page_label = Label.new()
	var pf := DynamicFont.new()
	pf.font_data = _pixel
	pf.size = 22 if standalone else 14
	page_label.add_font_override("font", pf)
	page_label.add_color_override("font_color", PAGE_GREEN)
	page_label.align = Label.ALIGN_CENTER
	page_label.rect_position = Vector2(0, 9)
	page_label.rect_size = Vector2(width, 18)
	add_child(page_label)

	prev_btn = _arrow("<", Vector2(0, frame_h / 2 - 16), "_prev")
	next_btn = _arrow(">", Vector2(width - arrows, frame_h / 2 - 16), "_next")

	# tiles for the buttons that exist; hide those buttons
	var hidden := {}
	for t in TILES:
		var target = mods.get_node_or_null(t[1])
		if target == null or not (target is BaseButton):
			continue
		var tl := Tile.new()
		tl.title = t[0]
		tl.icon = t[2]
		tl.color = t[3]
		tl.target = target
		if t[1].begins_with("SpeedMod"):
			tl.normal = mods.get_node_or_null("SpeedMod/C/Normal")
		tl.font = _label_font
		tl.hint_tooltip = target.hint_tooltip
		tl.rect_size = Vector2(tile, tile)
		add_child(tl)
		tiles.append(tl)
		if not t[1].begins_with("SpeedMod"):
			hidden[target] = true
	pages = int(ceil(tiles.size() / float(cols * rows)))
	for i in range(tiles.size()):
		var on_page := i % (cols * rows)
		var col := on_page % cols
		var row := on_page / cols
		tiles[i].rect_position = Vector2(
			arrows + FRAME_W + PAD + col * (tile + TILE_GAP),
			FRAME_W + TOP + row * (tile + TILE_GAP))

	if standalone:
		_show_page()
		return
	# the old rows: checkboxes hidden; the speed row keeps only "Custom"
	for n in hidden:
		n.visible = false
	var old_bottom := top_y
	for n in hidden:
		old_bottom = max(old_bottom, n.rect_position.y + n.rect_size.y)
	if speed:
		var c = speed.get_node_or_null("C")
		if c:
			for b in c.get_children():
				b.visible = b.name in ["Custom", "CustomSpeed"]
	# what was under the checkboxes (speed row, HP model, grade, 360 speed)
	# goes under the panel
	var below := []
	for n in mods.get_children():
		if n == self or hidden.has(n) or not (n is Control):
			continue
		if n == speed or n.rect_position.y >= old_bottom - 1:
			below.append(n)
	below.sort_custom(self, "_by_y")
	var y := top_y + frame_h + 10
	var first := true
	var base := 0.0
	for n in below:
		if n == speed:
			n.rect_position.y = y + 22 # its "Speed" label sits above it
			y += 56
			continue
		if first:
			base = n.rect_position.y
			first = false
		n.rect_position.y = y + (n.rect_position.y - base)
	var bottom := 0.0
	for n in mods.get_children():
		if n is Control and n.visible:
			bottom = max(bottom, n.rect_position.y + n.rect_size.y)
	mods.rect_min_size.y = bottom + 8
	_show_page()
	_ss_state = _snapshot()
	_sync()

# Visibility and height of everything under Mods (and the speed buttons), so
# switching Sound Space Mode can put either layout back.
func _snapshot() -> Dictionary:
	var nodes := {}
	for n in mods.get_children():
		if n != self and n is Control:
			nodes[n] = [n.visible, n.rect_position.y]
	var c = mods.get_node_or_null("SpeedMod/C")
	if c:
		for b in c.get_children():
			if b is Control:
				nodes[b] = [b.visible, null]
	return {"nodes": nodes, "min_y": mods.rect_min_size.y}

func _restore(st: Dictionary):
	for n in st.nodes:
		if is_instance_valid(n):
			n.visible = st.nodes[n][0]
			if st.nodes[n][1] != null:
				n.rect_position.y = st.nodes[n][1]
	mods.rect_min_size.y = st.min_y

func _process(_d):
	if not standalone:
		_sync()

func _sync():
	var on: bool = bool(Rhythia.get("sound_space_mode"))
	if on == _on:
		return
	_on = on
	visible = on
	_restore(_ss_state if on else _normal_state)
	# let the menu centre whichever layout is showing
	var menu = get_tree().current_scene if is_inside_tree() else null
	if menu != null and menu.has_method("_relayout_mods_soon"):
		menu.call_deferred("_relayout_mods_soon")

func _by_y(a, b) -> bool:
	return a.rect_position.y < b.rect_position.y

func _arrow(text: String, pos: Vector2, method: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	var f := DynamicFont.new()
	f.font_data = _pixel
	f.size = 22
	b.add_font_override("font", f)
	for k in ["font_color", "font_color_hover", "font_color_pressed"]:
		b.add_color_override(k, ARROW_CYAN)
	b.add_color_override("font_color_disabled", Color(ARROW_CYAN.r, ARROW_CYAN.g, ARROW_CYAN.b, 0.2))
	b.rect_position = pos
	b.rect_size = Vector2(24, 32)
	b.focus_mode = FOCUS_NONE
	b.connect("pressed", self, method)
	add_child(b)
	return b

func _prev():
	page = (page - 1 + pages) % pages
	_show_page()

func _next():
	page = (page + 1) % pages
	_show_page()

func _show_page():
	for i in range(tiles.size()):
		tiles[i].visible = i / (cols * rows) == page
	page_label.text = "%d/%d" % [page + 1, pages]
	prev_btn.visible = pages > 1
	next_btn.visible = pages > 1

class Frame extends Control:
	func _draw():
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.0, 0.0, 0.0, 0.55))
		draw_rect(Rect2(Vector2(2, 2), rect_size - Vector2(4, 4)), Color(1.0, 0.0, 0.95), false, 4.0)

# One modifier tile.
class Tile extends Control:
	var title := ""
	var icon := ""
	var color := Color(1, 1, 1)
	var target: BaseButton
	var normal: BaseButton # speed tiles: the "normal speed" button
	var font: Font
	var _on := false
	var _hover := false

	func _init():
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_set_hover", [true])
		connect("mouse_exited", self, "_set_hover", [false])

	func _set_hover(v: bool):
		_hover = v
		update()

	func _process(_d):
		var on: bool = is_instance_valid(target) and target.pressed
		if on != _on:
			_on = on
			update()

	func _gui_input(e):
		if e is InputEventMouseButton and e.button_index == BUTTON_LEFT and e.pressed:
			accept_event()
			if not is_instance_valid(target) or target.disabled:
				return
			if target.pressed and normal != null:
				# tapping the speed that's on goes back to normal speed
				normal.pressed = true
			else:
				target.pressed = not target.pressed
			update()

	func _rounded(r: Rect2, rad: float, col: Color, filled: bool, width: float = 1.0):
		var pts := PoolVector2Array()
		var steps := 6
		var corners := [
			[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2],
			[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
			[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
			[Vector2(r.position.x + rad, r.position.y + rad), PI],
		]
		for c in corners:
			for i in range(steps + 1):
				var a: float = c[1] + (PI / 2) * i / steps
				pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
		if filled:
			draw_colored_polygon(pts, col)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col, width, true)

	func _draw():
		var s := rect_size.x
		var col := color
		var lit := _on
		var a: float = 1.0 if lit else (0.75 if _hover else 0.5)
		var edge := Color(0.0, 0.9, 1.0) if lit else Color(col.r, col.g, col.b, a * 0.8)
		var r := Rect2(Vector2(3, 3), rect_size - Vector2(6, 6))
		_rounded(r, s * 0.14, Color(0.04, 0.04, 0.06, 0.92) if not lit else Color(0.0, 0.25, 0.3, 0.9), true)
		if lit:
			_rounded(r.grow(1.5), s * 0.15, Color(0.0, 0.9, 1.0, 0.35), false, 6.0)
		_rounded(r, s * 0.14, edge, false, max(2.0, s * 0.045))
		var ic := Color(0.0, 0.95, 1.0) if lit else Color(col.r, col.g, col.b, a)
		var c := Vector2(s / 2, s * 0.42)
		var u := s * 0.2
		_icon(c, u, ic)
		if font:
			var t := title
			# shrink long names to fit the tile
			var f: DynamicFont = font
			while f.get_string_size(t).x > s - 8 and f.size > 7:
				f = f.duplicate()
				f.size -= 1
			font = f
			var w := font.get_string_size(t).x
			var lc := Color(0.0, 0.95, 1.0) if lit else Color(0.8, 0.8, 0.85, a)
			draw_string(font, Vector2((s - w) / 2, s * 0.86), t, lc)

	func _chevrons(c: Vector2, u: float, n: int, dir: float, col: Color):
		var step := u * 0.55
		var total := step * (n - 1)
		for i in range(n):
			var x: float = c.x - total / 2 + i * step
			var tip := Vector2(x + dir * u * 0.35, c.y)
			draw_polyline(PoolVector2Array([Vector2(x - dir * u * 0.35, c.y - u * 0.7), tip, Vector2(x - dir * u * 0.35, c.y + u * 0.7)]), col, max(2.0, u * 0.28), true)

	func _heart(c: Vector2, u: float, col: Color, filled: bool):
		var pts := PoolVector2Array()
		for i in range(40):
			var t := TAU * i / 40.0
			var x := 16 * pow(sin(t), 3)
			var y := 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
			pts.append(c + Vector2(x, -y) * u / 15.0)
		if filled:
			draw_colored_polygon(pts, col)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col, max(2.0, u * 0.18), true)

	func _icon(c: Vector2, u: float, col: Color):
		var lw: float = max(2.0, u * 0.2)
		match icon:
			"nofail":
				draw_arc(c, u, 0, TAU, 32, col, lw, true)
				draw_line(c - Vector2(u * 0.55, 0), c + Vector2(u * 0.55, 0), col, lw)
				draw_line(c - Vector2(0, u * 0.55), c + Vector2(0, u * 0.55), col, lw)
			"ghost":
				draw_rect(Rect2(c - Vector2(u, u), Vector2(u, u) * 2), col, false, lw)
			"sudden":
				_heart(c, u, col, false)
				draw_polyline(PoolVector2Array([c + Vector2(-u * 0.1, -u * 0.6), c + Vector2(u * 0.15, -u * 0.1), c + Vector2(-u * 0.15, u * 0.2), c + Vector2(u * 0.1, u * 0.7)]), col, lw * 0.8, true)
			"heart":
				_heart(c, u, col, true)
			"noregen":
				_heart(c, u, col, false)
				draw_line(c + Vector2(-u, u), c + Vector2(u, -u), col, lw)
			"hard":
				draw_rect(Rect2(c - Vector2(u, u), Vector2(u, u) * 2), col, false, lw * 0.7)
				draw_rect(Rect2(c - Vector2(u, u) * 0.4, Vector2(u, u) * 0.8), col, true)
			"bolt":
				draw_colored_polygon(PoolVector2Array([c + Vector2(u * 0.2, -u * 1.1), c + Vector2(-u * 0.6, u * 0.15), c + Vector2(-u * 0.05, u * 0.15), c + Vector2(-u * 0.25, u * 1.1), c + Vector2(u * 0.6, -u * 0.2), c + Vector2(u * 0.05, -u * 0.2)]), col)
			"strobe":
				draw_rect(Rect2(c + Vector2(-u * 1.2, -u * 0.4), Vector2(u * 0.8, u * 0.8)), col, false, lw * 0.7)
				draw_rect(Rect2(c + Vector2(u * 0.4, -u * 0.4), Vector2(u * 0.8, u * 0.8)), col, false, lw * 0.7)
				for k in [-1, 1]:
					draw_line(c + Vector2(-u * 0.25, k * u * 0.75), c + Vector2(u * 0.25, k * u * 0.75), col, lw * 0.6)
			"mirrorx":
				draw_line(c - Vector2(0, u), c + Vector2(0, u), col, lw * 0.6)
				draw_colored_polygon(PoolVector2Array([c + Vector2(-u * 0.2, -u * 0.6), c + Vector2(-u * 1.1, 0), c + Vector2(-u * 0.2, u * 0.6)]), col)
				draw_colored_polygon(PoolVector2Array([c + Vector2(u * 0.2, -u * 0.6), c + Vector2(u * 1.1, 0), c + Vector2(u * 0.2, u * 0.6)]), col)
			"mirrory":
				draw_line(c - Vector2(u, 0), c + Vector2(u, 0), col, lw * 0.6)
				draw_colored_polygon(PoolVector2Array([c + Vector2(-u * 0.6, -u * 0.2), c + Vector2(0, -u * 1.1), c + Vector2(u * 0.6, -u * 0.2)]), col)
				draw_colored_polygon(PoolVector2Array([c + Vector2(-u * 0.6, u * 0.2), c + Vector2(0, u * 1.1), c + Vector2(u * 0.6, u * 0.2)]), col)
			"quake":
				var pts := PoolVector2Array()
				for i in range(7):
					pts.append(c + Vector2(-u * 1.1 + i * u * 2.2 / 6.0, (u * 0.6) * (1 if i % 2 == 0 else -1)))
				draw_polyline(pts, col, lw, true)
			"chaos":
				for p in [Vector2(-0.7, -0.6), Vector2(0.5, -0.8), Vector2(-0.2, 0.1), Vector2(0.75, 0.35), Vector2(-0.8, 0.75), Vector2(0.15, 0.85)]:
					draw_rect(Rect2(c + p * u - Vector2(u, u) * 0.18, Vector2(u, u) * 0.36), col, true)
			"eye":
				var pts2 := PoolVector2Array()
				for i in range(25):
					var t := PI * i / 24.0
					pts2.append(c + Vector2(-cos(t) * u * 1.2, -sin(t) * u * 0.65))
				for i in range(25):
					var t := PI * i / 24.0
					pts2.append(c + Vector2(cos(t) * u * 1.2, sin(t) * u * 0.65))
				pts2.append(pts2[0])
				draw_polyline(pts2, col, lw * 0.8, true)
				draw_circle(c, u * 0.32, col)
			"invert":
				draw_line(c + Vector2(-u, -u * 0.5), c + Vector2(u * 0.8, -u * 0.5), col, lw * 0.8)
				draw_colored_polygon(PoolVector2Array([c + Vector2(u * 1.1, -u * 0.5), c + Vector2(u * 0.6, -u * 0.85), c + Vector2(u * 0.6, -u * 0.15)]), col)
				draw_line(c + Vector2(u, u * 0.5), c + Vector2(-u * 0.8, u * 0.5), col, lw * 0.8)
				draw_colored_polygon(PoolVector2Array([c + Vector2(-u * 1.1, u * 0.5), c + Vector2(-u * 0.6, u * 0.15), c + Vector2(-u * 0.6, u * 0.85)]), col)
			"spin":
				draw_arc(c, u * 0.9, -PI * 0.35, PI * 1.45, 32, col, lw, true)
				var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * u * 0.9
				draw_colored_polygon(PoolVector2Array([tip + Vector2(u * 0.45, 0), tip + Vector2(-u * 0.15, -u * 0.45), tip + Vector2(-u * 0.1, u * 0.4)]), col)
			"light":
				draw_circle(c, u * 0.45, col)
				for i in range(8):
					var a := TAU * i / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * u * 0.7, c + Vector2(cos(a), sin(a)) * u * 1.1, col, lw * 0.7)
			_:
				if icon.begins_with("minus"):
					_chevrons(c, u, int(icon.substr(5)), -1.0, col)
				elif icon.begins_with("plus"):
					_chevrons(c, u, int(icon.substr(4)), 1.0, col)
