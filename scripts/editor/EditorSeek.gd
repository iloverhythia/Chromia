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

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	connect("resized", self, "mark_dirty")

func mark_dirty():
	_density_dirty = true
	update()

func _bar() -> Rect2:
	return Rect2(6, rect_size.y / 2 - 3, max(rect_size.x - 12, 1), 6)

func _ms_at(x: float) -> float:
	var b := _bar()
	return clamp((x - b.position.x) / b.size.x, 0.0, 1.0) * max(page.song_length_ms, 1.0)

func _gui_input(ev):
	if page == null or page.project == null:
		return
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_drag = ev.pressed
		if ev.pressed:
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
	# density above the bar
	var bw := b.size.x / max(_density.size(), 1)
	for i in range(_density.size()):
		var v := _density[i] / _density_peak
		if v <= 0.0:
			continue
		var hh := v * (rect_size.y / 2 - 6)
		draw_rect(Rect2(b.position.x + i * bw, b.position.y - hh - 2, max(bw - 1, 1), hh), Color(LILAC.r, LILAC.g, LILAC.b, 0.35))
	draw_rect(b, Color(1, 1, 1, 0.12))
	var p: float = clamp(page.time_ms / max(page.song_length_ms, 1.0), 0.0, 1.0)
	draw_rect(Rect2(b.position, Vector2(b.size.x * p, b.size.y)), LILAC)
	draw_circle(Vector2(b.position.x + b.size.x * p, b.position.y + b.size.y / 2), 7, ACCENT)
