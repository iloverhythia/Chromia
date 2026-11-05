extends Control

# Settings > a small "Watching Auto play" window that plays a short made-up
# map with your settings, drawn with the song's own notes, border, cursor,
# camera and hit effect (SettingsPreviewWorld.gd), so it looks the way a song
# does and you see what a change does straight away. Drag it by its title bar, resize it
# from the bottom-right corner, close it with the x (Settings > UI > Settings
# Preview turns it back on). Where it is and its size are saved.
#
# menu2.gd adds it to Main/Settings after the header (so it sits on top).

const TITLE_H := 24.0
const GRIP := 16.0
const MIN_SIZE := Vector2(230, 180)
const DEFAULT_SIZE := Vector2(330, 270)
const LOOP_S := 60.0

const BG_COL := Color(0.055, 0.05, 0.075, 0.97)
const TITLE_COL := Color(0.085, 0.078, 0.115, 1)
const EDGE_COL := Color(1, 1, 1, 0.12)
const DIM := Color(0.898, 0.949, 1, 0.5)
const TEXT := Color(0.898, 0.949, 1, 1)

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
	_make_view()

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
	_step_view(delta)

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
	var out := []
	for c in _raw_colors():
		out.append(Rhythia.note_color(c))
	return out

func _raw_colors() -> Array:
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

# --- the song, in 3D (SettingsPreviewWorld.gd), and the stats over it ----------

var _vc: ViewportContainer
var _vp: Viewport
var _world: Spatial
var _ov: Control
var _combo := 0
var _last_t := 0.0

func _make_view():
	_vc = ViewportContainer.new()
	_vc.stretch = true
	_vc.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_vc)
	_vp = Viewport.new()
	_vp.own_world = true
	_vp.msaa = Viewport.MSAA_4X
	_vp.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	_vp.size = Vector2(320, 240)
	_vc.add_child(_vp)
	_world = load("res://scripts/ui/settings/SettingsPreviewWorld.gd").new()
	_vp.add_child(_world)
	_ov = Control.new()
	_ov.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_ov)
	_ov.connect("draw", self, "_draw_overlay")

func _layout_view():
	var r := Rect2(1, TITLE_H, rect_size.x - 2, rect_size.y - TITLE_H - 1)
	if _vc.rect_position != r.position or _vc.rect_size != r.size:
		_vc.rect_position = r.position
		_vc.rect_size = r.size
		_ov.rect_position = r.position
		_ov.rect_size = r.size

func _step_view(delta: float):
	_layout_view()
	var t := _t
	if t < _last_t:
		_last_t = -1.0 # (the map started over)
	var colors := _colors()
	var ar: float = max(0.1, float(Rhythia.get("approach_rate")))
	var sd: float = max(0.1, float(Rhythia.get("spawn_distance")))
	var combo := 0
	var shown: Array = []
	var hits: Array = []
	for i in _notes.size():
		var n: Array = _notes[i]
		if n[0] <= t:
			combo += 1
			if n[0] > _last_t:
				hits.append([n[1], colors[i % colors.size()]])
			continue
		var dist: float = ar * (n[0] - t)
		if dist > sd:
			break
		shown.append([n[1], dist, colors[i % colors.size()], i])
	shown.invert() # (far ones first)
	_combo = combo
	_last_t = t
	var cc: Color = colors[(combo - 1) % colors.size()] if combo > 0 else colors[-1]
	_world.frame(delta, shown, _cursor_pos(t), hits, cc)
	_world.hud_frame(delta, t, LOOP_S, combo, _notes.size(), combo, cc) # (the song's own HUD panels)
	_ov.update()

func _draw_overlay():
	var w := _ov.rect_size.x
	var h := _ov.rect_size.y
	# (the HUD itself is the song's, in the 3D view: SettingsPreviewHud.gd)
	# resize grip
	var g := Vector2(w - 4, h - 4)
	for i in 3:
		var o: float = 4.0 + i * 4.0
		_ov.draw_line(g - Vector2(o, 0), g - Vector2(0, o), Color(1, 1, 1, 0.3), 1)

func _stat(pos: Vector2, width: float, label: String, value: String, right: bool):
	var ls := _f_small.get_string_size(label)
	var vs := _f_value.get_string_size(value)
	var lx := pos.x + (width - ls.x if right else 0.0)
	var vx := pos.x + (width - vs.x if right else 0.0)
	_ov.draw_string(_f_small, Vector2(lx, pos.y + _f_small.get_ascent()), label, DIM)
	_ov.draw_string(_f_value, Vector2(vx, pos.y + ls.y + 2 + _f_value.get_ascent()), value, TEXT)

func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
