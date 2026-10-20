extends Control
# Seek bar of the map editor: where you are in the song, how dense the notes
# are along it, and click / drag to jump.

var page # EditorPage
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
var _density: PoolRealArray = PoolRealArray()
var _density_peak := 1.0
var _density_dirty := true
var _drag := false
var _font: DynamicFont
var _font_b: DynamicFont
const TEXT = Color(0.898039, 0.94902, 1, 1)

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	connect("resized", self, "mark_dirty")
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_font.size = 12
	_font.use_filter = true
	_font_b = DynamicFont.new()
	_font_b.font_data = load("res://assets/font/Lato/Lato-Black.ttf")
	_font_b.size = 14
	_font_b.use_filter = true

func mark_dirty():
	_density_dirty = true
	update()

func _bar() -> Rect2:
	return Rect2(14, round(rect_size.y * 0.5) - 1, max(rect_size.x - 28, 1), 3)

func _ms_at(x: float) -> float:
	var b := _bar()
	return clamp((x - b.position.x) / b.size.x, 0.0, 1.0) * max(page.song_length_ms, 1.0)

func _gui_input(ev):
	if page == null or page.project == null:
		return
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_drag = ev.pressed
		if ev.pressed:
			if page.playing and page.pause_on_seek:
				page.pause()
			page.seek(_ms_at(ev.position.x))
		elif not page.playing:
			page.seek(page.snap_now(page.time_ms))
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		page.seek(_ms_at(ev.position.x))

func _rebuild_density():
	_density_dirty = false
	var buckets := int(max(_bar().size.x / 3, 1))
	_density = PoolRealArray()
	_density.resize(buckets)
	for i in range(buckets):
		_density[i] = 0.0
	var len_ms: float = max(page.song_length_ms, 1.0)
	for n in page.project.notes:
		var b := int(clamp(n[2] / len_ms, 0.0, 0.9999) * buckets)
		_density[b] += 1.0
	_density_peak = 1.0
	for v in _density:
		_density_peak = max(_density_peak, v)

func _draw():
	if page == null or page.project == null:
		return
	if _density_dirty:
		_rebuild_density()
	var b := _bar()
	var len_ms: float = max(page.song_length_ms, 1.0)
	# note density: a faint dotted strip under the line
	var bw := b.size.x / max(_density.size(), 1)
	for i in range(_density.size()):
		var v := _density[i] / _density_peak
		if v <= 0.0:
			continue
		draw_rect(Rect2(b.position.x + i * bw, b.position.y + 6, max(bw - 1, 1), 2), Color(1, 1, 1, 0.15 + 0.45 * v))
	draw_rect(b, ACCENT)
	var p: float = clamp(page.time_ms / len_ms, 0.0, 1.0)
	var kx := b.position.x + b.size.x * p
	draw_circle(Vector2(kx, b.position.y + 1), 6, LILAC)
	# current ms over the knob's side, times and note count under the line
	var ms_t: String = "%sms" % _comma(int(round(page.time_ms)))
	draw_string(_font_b, Vector2(2, b.position.y - 8), ms_t, TEXT)
	var by := b.position.y + 12 + _font_b.get_ascent()
	draw_string(_font_b, Vector2(0, by), _mmss(page.time_ms), TEXT)
	var lt := _mmss(len_ms)
	draw_string(_font_b, Vector2(rect_size.x - _font_b.get_string_size(lt).x, by), lt, TEXT)
	var nt: String = "%d Notes" % page.project.notes.size()
	draw_string(_font_b, Vector2((rect_size.x - _font_b.get_string_size(nt).x) / 2, by), nt, LILAC)

static func _mmss(ms: float) -> String:
	var t := int(max(ms, 0) / 1000)
	return "%d:%02d" % [t / 60, t % 60]

static func _comma(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
