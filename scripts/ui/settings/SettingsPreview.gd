extends Control

# Settings > a small "Watching Auto play" window that plays a short made-up
# map with your settings (approach rate, spawn distance, fade, half ghost,
# note size and opacity, colorset, cursor colour and size, hit effect), so you
# see what a change does straight away. Drag it by its title bar, resize it
# from the bottom-right corner, close it with the x (Settings > UI > Settings
# Preview turns it back on). Where it is and its size are saved.
#
# menu2.gd adds it to Main/Settings after the header (so it sits on top).

const TITLE_H := 24.0
const GRIP := 16.0
const MIN_SIZE := Vector2(230, 180)
const DEFAULT_SIZE := Vector2(330, 270)
const LOOP_S := 60.0
const CAM_D := 3.5 # (the game's camera is 3.5 units behind the grid)
const NOTE_FILL := 0.86 # a note's size next to a grid square

const BG_COL := Color(0.055, 0.05, 0.075, 0.97)
const TITLE_COL := Color(0.085, 0.078, 0.115, 1)
const EDGE_COL := Color(1, 1, 1, 0.12)
const DIM := Color(0.898, 0.949, 1, 0.5)
const TEXT := Color(0.898, 0.949, 1, 1)
const GRID_EDGE := Color(1, 1, 1, 0.55)
const GRID_LINE := Color(1, 1, 1, 0.07)

var _f_title: DynamicFont
var _f_small: DynamicFont
var _f_value: DynamicFont
var _f_combo: DynamicFont

var _notes: Array = [] # [time s, Vector2 cell (-1..1)]
var _t: float = 0.0
var _cursor_tex: Texture
var _drag := 0 # 0 none, 1 move, 2 resize
var _drag_from := Vector2()
var _drag_rect := Rect2()
var _placed := false

func _init():
	name = "SettingsPreview"
	mouse_filter = MOUSE_FILTER_STOP
	rect_clip_content = true
	var bold = load("res://assets/font/Lato/Lato-Bold.ttf")
	_f_title = _font(bold, 12)
	_f_small = _font(bold, 10)
	_f_value = _font(bold, 15)
	_f_combo = _font(bold, 22)
	_make_map()

func _font(data, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = data
	f.size = size
	f.use_filter = true
	return f

# a minute of notes: steady streams and jumps on the 3x3 grid, now and then
# between squares, like a real map
func _make_map():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	var t := 1.2
	var cell := Vector2(0, 0)
	while t < LOOP_S - 0.5:
		var step := 0.42
		var r := rng.randf()
		if r < 0.45:
			step = 0.3
		elif r < 0.75:
			step = 0.21
		var nxt := Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if rng.randf() < 0.15:
			nxt = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if nxt == cell:
			nxt.x = -nxt.x if nxt.x != 0 else 1.0
		cell = nxt
		_notes.append([t, cell])
		t += step
		if rng.randf() < 0.06:
			t += 0.8 # (a short break)

func _ready():
	var img = Globals.imageLoader.load_if_exists("user://cursor")
	_cursor_tex = img if img else load("res://assets/images/cursors/circle.png")
	var p = get_parent()
	if p is Control:
		p.connect("resized", self, "_fit")
	call_deferred("_place")

func _place():
	var r: Array = Rhythia.get("settings_preview_rect") if Rhythia.get("settings_preview_rect") is Array else []
	var p: Control = get_parent()
	if r.size() == 4:
		rect_position = Vector2(float(r[0]), float(r[1]))
		rect_size = Vector2(float(r[2]), float(r[3]))
	else:
		rect_size = DEFAULT_SIZE
		rect_position = Vector2(p.rect_size.x - DEFAULT_SIZE.x - 24, 96)
	_placed = true
	_fit()

# stays inside the Settings page (a smaller window, a different screen)
func _fit():
	var p = get_parent()
	if not (p is Control) or p.rect_size.x < 10:
		return
	var ps: Vector2 = p.rect_size
	rect_size.x = clamp(rect_size.x, MIN_SIZE.x, max(MIN_SIZE.x, ps.x - 8))
	rect_size.y = clamp(rect_size.y, MIN_SIZE.y, max(MIN_SIZE.y, ps.y - 8))
	rect_position.x = clamp(rect_position.x, 0, max(0, ps.x - rect_size.x))
	rect_position.y = clamp(rect_position.y, 0, max(0, ps.y - rect_size.y))

func _save_rect():
	Rhythia.set("settings_preview_rect", [round(rect_position.x), round(rect_position.y), round(rect_size.x), round(rect_size.y)])

func _process(delta):
	var on: bool = bool(Rhythia.get("settings_preview"))
	if visible != on:
		visible = on
	if not on or not is_visible_in_tree():
		return
	_t = fmod(_t + delta, LOOP_S)
	update()

# --- input ----------------------------------------------------------------

func _close_rect() -> Rect2:
	return Rect2(rect_size.x - TITLE_H, 0, TITLE_H, TITLE_H)

func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			if _close_rect().has_point(event.position):
				_close()
			elif event.position.x >= rect_size.x - GRIP and event.position.y >= rect_size.y - GRIP:
				_drag = 2
			elif event.position.y <= TITLE_H:
				_drag = 1
			if _drag != 0:
				_drag_from = event.global_position
				_drag_rect = Rect2(rect_position, rect_size)
			raise()
		elif _drag != 0:
			_drag = 0
			_save_rect()
		accept_event()
	elif event is InputEventMouseButton:
		accept_event() # (the wheel doesn't scroll the page under it)
	elif event is InputEventMouseMotion:
		if _drag == 1:
			rect_position = _drag_rect.position + (event.global_position - _drag_from)
			_fit()
		elif _drag == 2:
			rect_size = _drag_rect.size + (event.global_position - _drag_from)
			_fit()
		else:
			var p: Vector2 = event.position
			var shape := CURSOR_ARROW
			if p.x >= rect_size.x - GRIP and p.y >= rect_size.y - GRIP:
				shape = CURSOR_FDIAGSIZE
			elif _close_rect().has_point(p):
				shape = CURSOR_POINTING_HAND
			elif p.y <= TITLE_H:
				shape = CURSOR_MOVE
			if mouse_default_cursor_shape != shape:
				mouse_default_cursor_shape = shape
		accept_event()

func _close():
	Rhythia.set("settings_preview", false)
	visible = false
	var cb = get_parent().get_node_or_null("S/F/TabContainer/UI/UI/Group/H/SettingsPreview")
	if cb != null and cb.has_method("upd"):
		cb.upd()

# --- drawing ----------------------------------------------------------------

func _colors() -> Array:
	var cs = Rhythia.selected_colorset
	var c: Array = cs.colors if cs != null else []
	if c.empty():
		c = [Color(1, 0.756863, 0.960784), Color(0.6, 0.6, 0.6)]
	return c

func _linstep(a: float, b: float, x: float) -> float:
	if a == b:
		return float(x >= a)
	return clamp((x - a) / (b - a), 0, 1)

func _cursor_pos(t: float) -> Vector2:
	# glides from the last note to the next one, like autoplay
	var prev := Vector2(0, 0)
	var prev_t := 0.0
	for n in _notes:
		if n[0] > t:
			var k: float = clamp((t - prev_t) / max(0.001, n[0] - prev_t), 0, 1)
			k = k * k * (3 - 2 * k)
			return prev.linear_interpolate(n[1], k)
		prev = n[1]
		prev_t = n[0]
	return prev

func _draw():
	var w := rect_size.x
	var h := rect_size.y
	draw_rect(Rect2(Vector2(), rect_size), BG_COL)
	draw_rect(Rect2(0, 0, w, TITLE_H), TITLE_COL)
	draw_rect(Rect2(Vector2(), rect_size), EDGE_COL, false)

	# title bar
	var ty := (TITLE_H - _f_title.get_height()) / 2 + _f_title.get_ascent()
	draw_string(_f_title, Vector2(9, ty), "Watching", DIM)
	var x := 9 + _f_title.get_string_size("Watching ").x
	draw_string(_f_title, Vector2(x, ty), "Auto play", TEXT)
	x += _f_title.get_string_size("Auto play").x
	var right := "Settings Preview"
	var rw := _f_title.get_string_size(right).x
	if w - TITLE_H - rw - 4 > x + 10:
		draw_string(_f_title, Vector2(w - TITLE_H - rw - 2, ty), right, DIM)
	var c := _close_rect()
	var cc := c.position + c.size / 2
	var xc := Color(1, 1, 1, 0.65)
	draw_line(cc + Vector2(-4, -4), cc + Vector2(4, 4), xc, 1.6, true)
	draw_line(cc + Vector2(4, -4), cc + Vector2(-4, 4), xc, 1.6, true)

	var colors := _colors()
	var t := _t

	# progress bar and time
	var top := TITLE_H + 8
	var tstr := "%02d:%02d / %02d:%02d" % [int(t) / 60, int(t) % 60, int(LOOP_S) / 60, int(LOOP_S) % 60]
	var ts := _f_small.get_string_size(tstr)
	draw_string(_f_small, Vector2((w - ts.x) / 2, top + _f_small.get_ascent()), tstr, DIM)
	top += ts.y + 3
	var bar := Rect2(14, top, w - 28, 3)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * t / LOOP_S, bar.size.y)), colors[0])
	top += 10

	# the grid: square, between the side columns
	var side: float = clamp(w * 0.2, 46, 90)
	var avail_w := w - side * 2 - 8
	var avail_h := h - top - 10
	var gsz: float = max(30.0, min(avail_w, avail_h))
	var gpos := Vector2((w - gsz) / 2, top + (avail_h - gsz) / 2)
	var cell := gsz / 3.0
	var center := gpos + Vector2(gsz, gsz) / 2
	for i in range(1, 3):
		draw_line(gpos + Vector2(cell * i, 0), gpos + Vector2(cell * i, gsz), GRID_LINE, 1)
		draw_line(gpos + Vector2(0, cell * i), gpos + Vector2(gsz, cell * i), GRID_LINE, 1)
	draw_rect(Rect2(gpos, Vector2(gsz, gsz)), GRID_EDGE, false, 1.2)

	# notes: farthest first, so the near ones are drawn over them
	var ar: float = max(0.1, float(Rhythia.get("approach_rate")))
	var sd: float = max(0.1, float(Rhythia.get("spawn_distance")))
	var fl: float = float(Rhythia.get("fade_length"))
	var op: float = float(Rhythia.note_opacity)
	var nsize: float = float(Rhythia.note_size)
	var ghost: bool = bool(Rhythia.half_ghost)
	var gbase: float = clamp(float(Rhythia.half_ghost_strength), 0.1, 1.0)
	var combo := 0
	var shown: Array = []
	for i in _notes.size():
		var n: Array = _notes[i]
		if n[0] <= t:
			combo += 1
			continue
		var dist: float = ar * (n[0] - t)
		if dist > sd:
			break
		shown.append([i, n, dist])
	for j in range(shown.size() - 1, -1, -1):
		var i: int = shown[j][0]
		var n: Array = shown[j][1]
		var dist: float = shown[j][2]
		var alpha := op
		var fin := 1.0
		var fout := 1.0
		if fl != 0:
			fin = pow(_linstep(sd, sd * (1.0 - fl), dist), 1.3) * op
		if ghost:
			fout = ((1 - gbase) + pow(_linstep(3.0 / 50.0 * ar, 12.0 / 50.0 * ar, dist), 1.3) * gbase) * op
		if fl != 0 or ghost:
			alpha = min(fin, fout)
		if alpha <= 0.01:
			continue
		var k := CAM_D / (CAM_D + dist)
		var p: Vector2 = center + Vector2(n[1].x, -n[1].y) * cell * k
		var s := cell * NOTE_FILL * nsize * k
		var col: Color = colors[i % colors.size()]
		col.a *= alpha
		_draw_note(p, s, col)

	# hit effects: a ring that grows and fades where each note was hit
	if Rhythia.show_hit_effect:
		for i in range(max(0, combo - 6), combo):
			var n: Array = _notes[i]
			var age: float = t - n[0]
			if age < 0 or age > 0.35:
				continue
			var q := age / 0.35
			var hc: Color = colors[i % colors.size()]
			hc.a = (1 - q) * 0.8
			var hp: Vector2 = center + Vector2(n[1].x, -n[1].y) * cell
			var hs := cell * NOTE_FILL * nsize * (1 + q * 0.5)
			_draw_note(hp, hs, hc, 1.5)

	# the cursor
	var cp := _cursor_pos(t)
	var cpos: Vector2 = center + Vector2(cp.x, -cp.y) * cell
	var ccol := Color(1, 1, 1)
	var ctype := int(Rhythia.cursor_color_type)
	if ctype == Globals.CURSOR_CUSTOM_COLOR:
		ccol = Rhythia.cursor_color
	elif ctype == Globals.CURSOR_RAINBOW:
		ccol = Color.from_hsv(fmod(t * 0.5, 1.0), 0.65, 1)
	elif ctype == Globals.CURSOR_NOTE_COLOR:
		ccol = colors[(combo - 1) % colors.size()] if combo > 0 else colors[-1]
	if _cursor_tex != null:
		var csz := cell * 0.32 * float(Rhythia.cursor_scale)
		draw_texture_rect(_cursor_tex, Rect2(cpos - Vector2(csz, csz) / 2, Vector2(csz, csz)), false, ccol)

	# combo over the grid, stats down the sides
	var cstr := str(combo)
	draw_string(_f_combo, Vector2(gpos.x + 6, gpos.y + 4 + _f_combo.get_ascent()), cstr, Color(1, 1, 1, 0.8))
	var score := 0
	for i in combo:
		score += 25 * int(min(8, 1 + i / 10))
	var sy := gpos.y + gsz * 0.25
	_stat(Vector2(8, sy), side, "PAUSES", "0", false)
	_stat(Vector2(8, sy + 44), side, "ACCURACY", "100%", false)
	_stat(Vector2(w - side - 8, sy), side, "POINTS", _commas(score), true)
	_stat(Vector2(w - side - 8, sy + 44), side, "MISSES", "0", true)

	# resize grip
	var g := Vector2(w - 4, h - 4)
	for i in 3:
		var o: float = 4.0 + i * 4.0
		draw_line(g - Vector2(o, 0), g - Vector2(0, o), Color(1, 1, 1, 0.3), 1)

func _stat(pos: Vector2, width: float, label: String, value: String, right: bool):
	var ls := _f_small.get_string_size(label)
	var vs := _f_value.get_string_size(value)
	var lx := pos.x + (width - ls.x if right else 0.0)
	var vx := pos.x + (width - vs.x if right else 0.0)
	draw_string(_f_small, Vector2(lx, pos.y + _f_small.get_ascent()), label, DIM)
	draw_string(_f_value, Vector2(vx, pos.y + ls.y + 2 + _f_value.get_ascent()), value, TEXT)

func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

# a note: a rounded square outline, like the game's default note
func _draw_note(p: Vector2, s: float, col: Color, width: float = -1.0):
	if s < 1:
		return
	var r := s * 0.22
	var half := s / 2
	var lw: float = width if width > 0 else max(1.0, s * 0.1)
	var pts := PoolVector2Array()
	var corners := [Vector2(half - r, -half + r), Vector2(half - r, half - r), Vector2(-half + r, half - r), Vector2(-half + r, -half + r)]
	var start_ang := [-PI / 2, 0.0, PI / 2, PI]
	for ci in 4:
		for st in 5:
			var a: float = start_ang[ci] + (PI / 2) * st / 4.0
			pts.append(p + corners[ci] + Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, lw, true)
