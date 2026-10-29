extends Control
# The map editor's timeline along the bottom (SSQE's GuiSliderTimeline, ported
# from Sound Space Quantum Editor Plus's editor.js TimelineSlider): the whole
# song with ticks for notes, timing points and objects, the part the track
# shows, and bookmarks above it. Drag to seek; click a bookmark to go to its
# start (Shift: its end), right-click for its end (Shift: its start).

const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")

var ed
var dragging := false
var hovering_bookmark = null
var _was_playing := false
var _hover := 0.0
var _hovering := false

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	connect("mouse_entered", self, "_set_hover", [true])
	connect("mouse_exited", self, "_set_hover", [false])

func _set_hover(on: bool):
	_hovering = on

func line_rect() -> Rect2:
	return Rect2(rect_size.y / 2, rect_size.y / 2 - 1.5, rect_size.x - rect_size.y, 3)

func _bookmark_rect(b, line: Rect2, mx: float) -> Rect2:
	var y := line.position.y + line.size.y / 2
	var x: float = line.position.x + b.ms / mx * line.size.x
	var end_x: float = line.position.x + b.end_ms / mx * line.size.x
	return Rect2(x - 4, y - 40 * ed.hd, 8 + (end_x - x), 8 * ed.hd)

# the bookmarks above the line count as the timeline too
func has_point(point: Vector2) -> bool:
	if Rect2(Vector2(), rect_size).has_point(point):
		return true
	if ed == null or ed.map == null:
		return false
	var line := line_rect()
	var mx: float = max(ed.total_time(), 1.0)
	for b in ed.map.bookmarks:
		if _bookmark_rect(b, line, mx).grow(2).has_point(point):
			return true
	return false

func _update_hover(p: Vector2):
	hovering_bookmark = null
	if ed.map == null:
		return
	var line := line_rect()
	var mx: float = max(ed.total_time(), 1.0)
	for b in ed.map.bookmarks:
		if _bookmark_rect(b, line, mx).grow(2).has_point(p):
			hovering_bookmark = b

func _set_from(x: float):
	var line := line_rect()
	var total: float = max(ed.total_time(), 1.0)
	var step := total / 2000.0
	var prog: float = clamp((x - line.position.x) / max(line.size.x, 1), 0, 1)
	var v := round(prog * total / step) * step
	ed.set_current_time(clamp(v, 0, total))

func _gui_input(ev):
	if ed == null or ed.map == null:
		return
	if ev is InputEventMouseMotion:
		_update_hover(ev.position)
		if dragging:
			_set_from(ev.position.x)
		accept_event()
	elif ev is InputEventMouseButton:
		_update_hover(ev.position)
		var shift: bool = Input.is_key_pressed(KEY_SHIFT)
		if ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				if hovering_bookmark != null:
					if ed.playing:
						ed.pause_music()
					ed.set_current_time(hovering_bookmark.end_ms if shift else hovering_bookmark.ms)
				else:
					_was_playing = ed.playing
					if ed.playing:
						ed.pause_music()
					dragging = true
					_set_from(ev.position.x)
			else:
				if dragging and _was_playing and not ed.s.pauseScroll:
					ed.play_music()
				dragging = false
			accept_event()
		elif ev.button_index == BUTTON_RIGHT and ev.pressed:
			if hovering_bookmark != null:
				if ed.playing:
					ed.pause_music()
				ed.set_current_time(hovering_bookmark.ms if shift else hovering_bookmark.end_ms)
			accept_event()
		elif ev.pressed and (ev.button_index == BUTTON_WHEEL_UP or ev.button_index == BUTTON_WHEEL_DOWN):
			ed.on_wheel(1 if ev.button_index == BUTTON_WHEEL_UP else -1)
			accept_event()

var _tick_key := ""
var _tick_rects := []

func _process(delta):
	var target := 1.0 if (_hovering or dragging) else 0.0
	_hover = move_toward(_hover, target, delta * 10.0)

func _draw():
	if ed == null or ed.map == null:
		return
	var map = ed.map
	var s: Dictionary = ed.s
	var line := line_rect()
	var mx: float = max(ed.total_time(), 1.0)
	var y := line.position.y + line.size.y / 2
	draw_rect(line, SSQESettings.color(s, "color2"))
	draw_rect(Rect2(line.position.x + ed.track_start_rel * line.size.x, line.position.y, (ed.track_end_rel - ed.track_start_rel) * line.size.x, line.size.y), SSQESettings.color(s, "color3"))
	var c := Vector2(line.position.x + line.size.x * (ed.current_time() / mx), y)
	var c1 := SSQESettings.color(s, "color1")
	draw_circle(c, 4, c1)
	if _hover > 0:
		var radius := 12.0 * _hover
		var rot := deg2rad(90.0 * _hover)
		var pts := PoolVector2Array()
		for k in range(7):
			var a := rot + k * PI / 3
			pts.append(c + Vector2(cos(a), sin(a)) * radius)
		draw_polyline(pts, c1, 2, true)
	# bookmarks
	for b in map.bookmarks:
		var col := SSQESettings.color(s, "color2", 0.75) if hovering_bookmark == b else SSQESettings.color(s, "color3", 0.75)
		draw_rect(_bookmark_rect(b, line, mx), col)
	# ticks: worked out again only after an edit, a drag, or a size change
	# (every object, every frame, was slow on big maps)
	var wdiff: float = ed.wd
	var key := "%d|%s|%f|%f|%d|%d|%d|%d" % [ed.edit_count, str(line), mx, wdiff, map.notes.items.size(), map.timing_points.size(), map.vfx_objects.items.size(), map.special_objects.items.size()]
	if key != _tick_key or not ed.dragging_objects.empty():
		_tick_key = key
		_tick_rects = []
		_ticks(map.notes.items, line, mx, y + 5, y + 3, 1 * wdiff)
		_ticks(map.timing_points, line, mx, y - 10, y - 6, 2 * wdiff)
		_ticks(map.vfx_objects.items, line, mx, y + 9, y + 7, 2 * wdiff)
		_ticks(map.special_objects.items, line, mx, y + 9, y + 7, 2 * wdiff)
	for r in _tick_rects:
		draw_rect(r, Color(1, 1, 1))
	if hovering_bookmark != null:
		var f: DynamicFont = ed.font(int(round(16 * min(ed.wd, ed.hd) * 0.9 + 4)))
		var bx: float = line.position.x + hovering_bookmark.ms / mx * line.size.x
		draw_string(f, Vector2(bx, y - 40 * ed.hd - 4), hovering_bookmark.text, SSQESettings.color(s, "color2"))

func _ticks(items: Array, line: Rect2, mx: float, y1: float, y2: float, width: float):
	var prev := -1.0
	var top: float = min(y1, y2)
	var h: float = abs(y2 - y1)
	var scale := line.size.x / mx
	for o in items:
		var x: float = line.position.x + o.ms * scale
		if x - 1 >= prev:
			_tick_rects.append(Rect2(x - width / 2, top, max(width, 1), h))
			prev = x
