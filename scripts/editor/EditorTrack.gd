extends Control
# The track along the top of the map editor: beat lines for the beat divisor
# and every note as a small 3x3 box at its time, with the playhead fixed at
# PLAYHEAD of the width.
# - wheel: move by one snap step (Ctrl: zoom, Shift: change the beat divisor)
# - click a note: select it (Shift/Ctrl: add), drag: move selected notes in time
# - drag empty space: scrub; right-drag: box select

var page # EditorPage
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)

var _font: DynamicFont
var _font_b: DynamicFont
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
	_font.size = 11
	_font.use_filter = true
	_font_b = DynamicFont.new()
	_font_b.font_data = load("res://assets/font/Lato/Lato-Black.ttf")
	_font_b.size = 11
	_font_b.use_filter = true

# the grey band; the note labels hang below it (like SSQE)
func _band_h() -> float:
	return round(rect_size.y * 0.62)

func x_at(ms: float) -> float:
	return rect_size.x * page.cursor_position + (ms - page.time_ms) * page.zoom

func ms_at(x: float) -> float:
	return page.time_ms + (x - rect_size.x * page.cursor_position) / page.zoom

func _box_size() -> float:
	return clamp(_band_h() * 0.55, 18, 44)

func _box_y() -> float:
	return (_band_h() - _box_size()) / 2 - 4

# index of the note whose box is under x (closest one)
func _note_at(pos: Vector2) -> int:
	var b := _box_size()
	if pos.y < _box_y() - 4 or pos.y > _box_y() + b + 4:
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
	var bh := _band_h()
	draw_rect(Rect2(0, 0, w, bh), Color(0.15, 0.14, 0.18, 1))
	draw_line(Vector2(0, bh), Vector2(w, bh), Color(1, 1, 1, 0.08), 1.0)
	var pr = page.project
	var left := ms_at(0)
	var right := ms_at(w)

	# outside the song
	var end_x := x_at(page.song_length_ms)
	var start_x := x_at(0)
	if start_x > 0:
		draw_rect(Rect2(0, 0, start_x, bh), Color(0, 0, 0, 0.35))
	if end_x < w:
		draw_rect(Rect2(end_x, 0, w - end_x, bh), Color(0, 0, 0, 0.35))
	# centre line (SSQE draws the waveform here)
	draw_line(Vector2(max(start_x, 0), bh / 2), Vector2(min(end_x, w), bh / 2), Color(1, 1, 1, 0.12), 1.0)

	# beat ticks along the bottom of the band
	var step: float = pr.beat_ms() / max(page.divisor, 1)
	var div: int = page.divisor
	var show_sub: bool = step * page.zoom >= 5.0
	var k := int(ceil((left - pr.offset) / step))
	var guard := 0
	while guard < 4000:
		guard += 1
		var ms: float = pr.offset + k * step
		if ms > right:
			break
		var x := x_at(ms)
		if posmod(k, div) == 0:
			var measure := posmod(k / div, 4) == 0
			draw_line(Vector2(x, bh - (bh * 0.3 if measure else bh * 0.18)), Vector2(x, bh), Color(1, 1, 1, 0.55 if measure else 0.35), 1.0)
		elif show_sub:
			draw_line(Vector2(x, bh - bh * 0.09), Vector2(x, bh), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45), 1.0)
		k += 1

	# box selection
	if _mode == "box":
		var a := x_at(min(_box_from, _box_to))
		var b := x_at(max(_box_from, _box_to))
		draw_rect(Rect2(a, 0, b - a, bh), Color(LILAC.r, LILAC.g, LILAC.b, 0.15))
		draw_rect(Rect2(a, 0, b - a, bh), Color(LILAC.r, LILAC.g, LILAC.b, 0.6), false, 1.0)

	# notes: 3x3 boxes, labels under the band
	var bs := _box_size()
	var by := _box_y()
	var c := bs / 3.0
	var notes: Array = pr.notes
	var i: int = pr.lower_bound(left - 60.0 / max(page.zoom, 0.01))
	var last_label_x := -1e9
	while i < notes.size() and notes[i][2] <= right + bs / max(page.zoom, 0.01):
		var n = notes[i]
		var x := x_at(n[2])
		var col: Color = page.note_color(i)
		var sel: bool = page.is_selected(n[3])
		var past: bool = n[2] < page.time_ms - 1.0
		var a := 0.45 if past else 1.0
		var r := Rect2(round(x - bs / 2), by, bs, bs)
		draw_rect(r, Color(0, 0, 0, 0.6))
		for gx in range(1, 3):
			draw_line(r.position + Vector2(gx * c, 2), r.position + Vector2(gx * c, bs - 2), Color(col.r, col.g, col.b, 0.3 * a), 1.0)
			draw_line(r.position + Vector2(2, gx * c), r.position + Vector2(bs - 2, gx * c), Color(col.r, col.g, col.b, 0.3 * a), 1.0)
		var cp := r.position + Vector2(clamp(n[0], -0.5, 2.5), clamp(n[1], -0.5, 2.5)) * c
		draw_rect(Rect2(cp + Vector2(2, 2), Vector2(c - 4, c - 4)), Color(col.r, col.g, col.b, a))
		draw_rect(r, Color(1, 1, 1) if sel else Color(col.r, col.g, col.b, a), false, 2.0 if sel else 1.0)
		# labels, when there's room
		if r.position.x - last_label_x > 46 or sel:
			draw_line(Vector2(r.position.x, bh), Vector2(r.position.x, bh + 4), Color(1, 1, 1, 0.5 * a), 1.0)
			draw_string(_font_b, Vector2(r.position.x + 2, bh + 4 + _font_b.get_ascent()), "Note %d" % (i + 1), Color(LILAC.r, LILAC.g, LILAC.b, a) if not sel else Color(1, 1, 1))
			draw_string(_font, Vector2(r.position.x + 2, bh + 4 + _font_b.get_height() + _font.get_ascent() - 2), "%sms" % _comma(int(round(n[2]))), Color(ACCENT.r, ACCENT.g, ACCENT.b, a))
			last_label_x = r.position.x
		i += 1

	# playhead
	var px: float = w * page.cursor_position
	draw_line(Vector2(px, 0), Vector2(px, bh), ACCENT, 2.0)

static func _comma(v: int) -> String:
	var s := str(abs(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
