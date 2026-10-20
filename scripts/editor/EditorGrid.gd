extends Control
# The 3x3 grid of the map editor (like Sound Space Quantum Editor's): notes
# coming up are drawn as approach squares closing in on their cell, the notes at
# the current time solid. Click an empty spot to place a note at the current
# (snapped) time, click a note to select it and drag to move it, right-click a
# note to delete it. With Quantum on, notes go between cells too.

var page # EditorPage
const KEYS = ["Q", "W", "E", "A", "S", "D", "Z", "X", "C"]
const LILAC = Color(0.764706, 0.65098, 0.8)
const FADE_MS = 150.0

var _hover := Vector2(-10, -10) # grid position under the mouse
var _dragging := false
var _drag_uids: Array = []
var _drag_start := Vector2()
var _drag_moved := false
var _font: DynamicFont

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Black.ttf")
	_font.size = 30
	_font.use_filter = true
	connect("mouse_exited", self, "_on_exit")

func _on_exit():
	_hover = Vector2(-10, -10)
	update()

func _geom() -> Array:
	var s: float = floor(min(rect_size.x, rect_size.y))
	var origin := Vector2(floor((rect_size.x - s) / 2), floor((rect_size.y - s) / 2))
	return [origin, s / 3.0]

func to_grid(p: Vector2) -> Vector2:
	var g = _geom()
	return (p - g[0]) / g[1] - Vector2(0.5, 0.5)

func _placement(gp: Vector2) -> Vector2:
	if page.quantum:
		var q: float = float(max(page.quantum_divisor, 1))
		var v := Vector2(round(gp.x * q) / q, round(gp.y * q) / q)
		return Vector2(clamp(v.x, -0.5, 2.5), clamp(v.y, -0.5, 2.5))
	return Vector2(clamp(round(gp.x), 0, 2), clamp(round(gp.y), 0, 2))

func _in_grid(gp: Vector2) -> bool:
	var lim := 1.0 if page.quantum else 0.5
	return gp.x >= -lim and gp.x <= 2.0 + lim and gp.y >= -lim and gp.y <= 2.0 + lim

func _gui_input(ev):
	if page == null or page.project == null:
		return
	if ev is InputEventMouseMotion:
		var gp := to_grid(ev.position)
		_hover = _placement(gp) if _in_grid(gp) else Vector2(-10, -10)
		if _dragging and not _drag_uids.empty():
			var target := _placement(gp)
			var delta: Vector2 = target - _drag_start
			if delta != Vector2.ZERO:
				if not _drag_moved:
					page.push_undo()
					_drag_moved = true
				page.move_notes_by(_drag_uids, delta)
				_drag_start = target
		update()
	elif ev is InputEventMouseButton and ev.pressed:
		var gp := to_grid(ev.position)
		if not _in_grid(gp):
			return
		var pos := _placement(gp)
		var hit = page.note_at_current(gp)
		if ev.button_index == BUTTON_LEFT:
			if hit != null:
				if ev.shift or ev.control:
					page.toggle_select(hit[3])
				elif not page.is_selected(hit[3]):
					page.select_only([hit[3]])
				_dragging = true
				_drag_moved = false
				_drag_uids = page.selected_uids_at_current()
				_drag_start = pos
			else:
				page.place_note(pos)
			accept_event()
		elif ev.button_index == BUTTON_RIGHT:
			if hit != null:
				page.delete_uids([hit[3]])
			accept_event()
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == BUTTON_LEFT:
		_dragging = false
		_drag_uids = []
		if _drag_moved:
			page.notes_changed()
		_drag_moved = false

func _draw():
	if page == null or page.project == null:
		return
	var g = _geom()
	var o: Vector2 = g[0]
	var cell: float = g[1]
	var size: float = cell * 3.0
	draw_rect(Rect2(o, Vector2(size, size)), Color(0.06, 0.055, 0.08, 0.92))
	# cells
	for i in range(9):
		var cx := i % 3
		var cy := i / 3
		var r := Rect2(o + Vector2(cx, cy) * cell, Vector2(cell, cell))
		draw_rect(r.grow(-1), Color(1, 1, 1, 0.025))
		if page.show_letters:
			var t: String = KEYS[i]
			var ts := _font.get_string_size(t)
			draw_string(_font, r.position + (r.size - ts) / 2 + Vector2(0, _font.get_ascent()), t, Color(1, 1, 1, 0.07))
	# grid lines
	for k in range(4):
		var c := Color(1, 1, 1, 0.14 if k == 0 or k == 3 else 0.08)
		draw_line(o + Vector2(k * cell, 0), o + Vector2(k * cell, size), c, 1.0)
		draw_line(o + Vector2(0, k * cell), o + Vector2(size, k * cell), c, 1.0)
	if page.quantum and page.quantum_divisor > 1:
		var q: int = page.quantum_divisor
		var qc := Color(LILAC.r, LILAC.g, LILAC.b, 0.07)
		# lines through every spot a quantum note can sit (cell centres + fractions)
		for k in range(-q, 3 * q + 1):
			if k % q == 0:
				continue
			var f := (float(k) / q + 0.5) * cell
			if f <= 0.0 or f >= size:
				continue
			draw_line(o + Vector2(f, 0), o + Vector2(f, size), qc, 1.0)
			draw_line(o + Vector2(0, f), o + Vector2(size, f), qc, 1.0)

	# hover
	if _hover.x > -5:
		var hc: Vector2 = o + (_hover + Vector2(0.5, 0.5)) * cell
		var hs := cell * 0.86
		draw_rect(Rect2(hc - Vector2(hs, hs) / 2, Vector2(hs, hs)), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(hc - Vector2(hs, hs) / 2, Vector2(hs, hs)), Color(1, 1, 1, 0.18), false, 1.0)

	# notes
	var now: float = page.time_ms
	var ar: float = page.approach_ms
	var notes: Array = page.project.notes
	var i0: int = page.project.lower_bound(now - FADE_MS)
	var ns := cell * 0.86
	var j := i0
	# far notes first so near ones draw on top
	var vis := []
	while j < notes.size() and notes[j][2] <= now + ar:
		vis.append(j)
		j += 1
	vis.invert()
	for idx in vis:
		var n = notes[idx]
		var dt: float = n[2] - now
		var col: Color = page.note_color(idx)
		var center: Vector2 = o + (Vector2(n[0], n[1]) + Vector2(0.5, 0.5)) * cell
		var sel: bool = page.is_selected(n[3])
		if abs(dt) <= 1.0:
			draw_rect(Rect2(center - Vector2(ns, ns) / 2, Vector2(ns, ns)), Color(col.r, col.g, col.b, 0.95))
			if sel:
				draw_rect(Rect2(center - Vector2(ns, ns) / 2 - Vector2(3, 3), Vector2(ns + 6, ns + 6)), LILAC.lightened(0.3), false, 3.0)
		elif dt < 0:
			var a := 1.0 + dt / FADE_MS
			draw_rect(Rect2(center - Vector2(ns, ns) / 2, Vector2(ns, ns)), Color(col.r, col.g, col.b, 0.6 * a))
		else:
			var p: float = clamp(dt / max(ar, 1.0), 0.0, 1.0)
			var s := ns * (1.0 - p * 0.75) # grows into the cell as it approaches
			var a := (1.0 - p) * 0.9
			draw_rect(Rect2(center - Vector2(s, s) / 2, Vector2(s, s)), Color(col.r, col.g, col.b, a), false, 3.0)
			if sel:
				draw_rect(Rect2(center - Vector2(s, s) / 2 - Vector2(3, 3), Vector2(s + 6, s + 6)), Color(LILAC.r, LILAC.g, LILAC.b, a), false, 1.5)

	# autoplay cursor: glides between notes while playing
	if page.show_cursor and not notes.empty():
		var cp = page.cursor_pos()
		if cp != null:
			var cc: Vector2 = o + (cp + Vector2(0.5, 0.5)) * cell
			draw_circle(cc, cell * 0.09, Color(1, 1, 1, 0.9))
			draw_arc(cc, cell * 0.12, 0, TAU, 24, Color(0, 0, 0, 0.5), 2.0)
