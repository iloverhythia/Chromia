extends Control
# The track along the top of the map editor: beat lines for the beat divisor
# and every note as a small 3x3 box at its time, with the playhead fixed at
# PLAYHEAD of the width.
# - wheel: move by one snap step (Ctrl: zoom, Shift: change the beat divisor)
# - click a note: select it (Shift/Ctrl: add), drag: move selected notes in time
# - drag empty space: scrub; right-drag: box select

var page # EditorPage
const LILAC = Color(0.764706, 0.65098, 0.8)
const PLAYHEAD = 0.3

var _font: DynamicFont
var _mode := "" # "", "scrub", "move", "box"
var _press_ms := 0.0
var _press_x := 0.0
var _move_anchor_ms := 0.0
var _move_applied := 0.0
var _box_from := 0.0
var _box_to := 0.0
var _undo_pushed := false

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	rect_clip_content = true
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_font.size = 12
	_font.use_filter = true

func x_at(ms: float) -> float:
	return rect_size.x * PLAYHEAD + (ms - page.time_ms) * page.zoom

func ms_at(x: float) -> float:
	return page.time_ms + (x - rect_size.x * PLAYHEAD) / page.zoom

func _box_size() -> float:
	return clamp(rect_size.y - 34, 24, 54)

# index of the note whose box is under x (closest one)
func _note_at(pos: Vector2) -> int:
	var b := _box_size()
	if pos.y < 6 or pos.y > 6 + b:
		return -1
	var notes: Array = page.project.notes
	var lo: int = page.project.lower_bound(ms_at(pos.x - b / 2))
	var best := -1
	var best_d := 1e9
	var i := lo
	while i < notes.size():
		var x := x_at(notes[i][2])
		if x - b / 2 > pos.x:
			break
		var d: float = abs(x - pos.x)
		if d <= b / 2 and d < best_d:
			best = i
			best_d = d
		i += 1
	return best

func _gui_input(ev):
	if page == null or page.project == null:
		return
	if ev is InputEventMouseButton:
		if ev.pressed and ev.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			var up: bool = ev.button_index == BUTTON_WHEEL_UP
			if ev.control:
				page.set_zoom(page.zoom * (1.15 if up else 1.0 / 1.15))
			elif ev.shift:
				page.change_divisor(1 if up else -1)
			else:
				page.step(1 if up else -1)
			accept_event()
			return
		if ev.button_index == BUTTON_LEFT and ev.pressed:
			var i := _note_at(ev.position)
			if i >= 0:
				var n = page.project.notes[i]
				var stack: Array = page.uids_at_ms(n[2])
				if ev.shift or ev.control:
					for u in stack:
						page.toggle_select(u)
				elif not page.is_selected(n[3]):
					page.select_only(stack)
				_mode = "move"
				_move_anchor_ms = n[2]
				_move_applied = 0.0
				_undo_pushed = false
			else:
				_mode = "scrub"
				page.pause()
				_press_ms = page.time_ms
				_press_x = ev.position.x
			accept_event()
		elif ev.button_index == BUTTON_RIGHT and ev.pressed:
			_mode = "box"
			_box_from = ms_at(ev.position.x)
			_box_to = _box_from
			accept_event()
		elif not ev.pressed and (ev.button_index == BUTTON_LEFT or ev.button_index == BUTTON_RIGHT):
			if _mode == "box":
				page.select_range(min(_box_from, _box_to), max(_box_from, _box_to), Input.is_key_pressed(KEY_SHIFT))
			elif _mode == "move" and _undo_pushed:
				page.notes_changed()
			elif _mode == "scrub":
				page.seek(page.snap_now(page.time_ms))
			_mode = ""
			update()
	elif ev is InputEventMouseMotion:
		if _mode == "scrub":
			# dragging the track moves time the other way (like grabbing paper)
			var ms: float = _press_ms - (ev.position.x - _press_x) / page.zoom
			page.seek(ms)
		elif _mode == "move":
			var target: float = page.project.snap(ms_at(ev.position.x), page.divisor)
			var delta: float = target - _move_anchor_ms
			if abs(delta - _move_applied) > 0.5:
				if not _undo_pushed:
					page.push_undo()
					_undo_pushed = true
				page.shift_selected_ms(delta - _move_applied)
				_move_applied = delta
		elif _mode == "box":
			_box_to = ms_at(ev.position.x)
			update()

func _draw():
	if page == null or page.project == null:
		return
	var w := rect_size.x
	var h := rect_size.y
	draw_rect(Rect2(Vector2(), rect_size), Color(0.07, 0.065, 0.09, 0.95))
	var pr = page.project
	var left := ms_at(0)
	var right := ms_at(w)

	# song bounds
	var end_x := x_at(page.song_length_ms)
	var start_x := x_at(0)
	if start_x > 0:
		draw_rect(Rect2(0, 0, start_x, h), Color(0, 0, 0, 0.35))
	if end_x < w:
		draw_rect(Rect2(end_x, 0, w - end_x, h), Color(0, 0, 0, 0.35))

	# beat lines
	var step: float = pr.beat_ms() / max(page.divisor, 1)
	var div: int = page.divisor
	var show_sub: bool = step * page.zoom >= 5.0
	var k0 := int(ceil((left - pr.offset) / step))
	var k := k0
	var guard := 0
	while guard < 4000:
		guard += 1
		var ms: float = pr.offset + k * step
		if ms > right:
			break
		var x := x_at(ms)
		var on_beat := posmod(k, div) == 0
		if on_beat:
			var beat := k / div
			var measure := posmod(beat, 4) == 0
			draw_line(Vector2(x, h * (0.25 if measure else 0.5)), Vector2(x, h), Color(1, 1, 1, 0.35 if measure else 0.22), 1.0)
		elif show_sub:
			draw_line(Vector2(x, h * 0.78), Vector2(x, h), Color(LILAC.r, LILAC.g, LILAC.b, 0.35), 1.0)
		k += 1

	# box selection
	if _mode == "box":
		var a := x_at(min(_box_from, _box_to))
		var b := x_at(max(_box_from, _box_to))
		draw_rect(Rect2(a, 0, b - a, h), Color(LILAC.r, LILAC.g, LILAC.b, 0.15))
		draw_rect(Rect2(a, 0, b - a, h), Color(LILAC.r, LILAC.g, LILAC.b, 0.6), false, 1.0)

	# notes
	var bs := _box_size()
	var notes: Array = pr.notes
	var i0: int = pr.lower_bound(left - 200.0 / max(page.zoom, 0.01))
	var i := i0
	var drawn := []
	while i < notes.size() and notes[i][2] <= right + bs / max(page.zoom, 0.01):
		drawn.append(i)
		i += 1
	# backgrounds first so stacked notes (same time) show all their cells
	for idx in drawn:
		var n = notes[idx]
		var x := x_at(n[2])
		var r := Rect2(x - bs / 2, 6, bs, bs)
		draw_rect(r, Color(0.12, 0.11, 0.15, 1))
	for idx in drawn:
		var n = notes[idx]
		var x := x_at(n[2])
		var r := Rect2(x - bs / 2, 6, bs, bs)
		var c := bs / 3.0
		var cp := r.position + Vector2(clamp(n[0], -0.5, 2.5), clamp(n[1], -0.5, 2.5)) * c
		draw_rect(Rect2(cp + Vector2(1, 1), Vector2(c - 2, c - 2)), page.note_color(idx))
	for idx in drawn:
		var n = notes[idx]
		var x := x_at(n[2])
		var r := Rect2(x - bs / 2, 6, bs, bs)
		var sel: bool = page.is_selected(n[3])
		draw_rect(r, LILAC if sel else Color(1, 1, 1, 0.2), false, 2.0 if sel else 1.0)
		if sel:
			var t := "%d" % int(round(n[2]))
			draw_string(_font, Vector2(x - _font.get_string_size(t).x / 2, 6 + bs + 14), t, LILAC)

	# playhead
	var px := w * PLAYHEAD
	draw_line(Vector2(px, 0), Vector2(px, h), Color(1, 0.756863, 0.960784), 2.0)
