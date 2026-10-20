extends Control
# The 3x3 grid of the map editor (like Sound Space Quantum Editor's): notes
# coming up are drawn as approach squares closing in on their cell, the notes at
# the current time solid. Click an empty spot to place a note at the current
# (snapped) time, click a note to select it and drag to move it, right-click a
# note to delete it. With Quantum on, notes go between cells too.

var page # EditorPage
const KEYS = ["Q", "W", "E", "A", "S", "D", "Z", "X", "C"]
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
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
	_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_font.size = 30
	_font.use_filter = true
	connect("mouse_exited", self, "_on_exit")

func _on_exit():
	_hover = Vector2(-10, -10)
	update()

func _3d() -> bool:
	return page != null and page.view3d != null and page.game_view and page.view3d.is_built()

func _geom() -> Array:
	if _3d():
		return page.view3d.grid_geom()
	# SSQE's grid: 200 px (at 720p) in the middle of its frame
	var sc: float = page._scale
	var sz: float = round(200.0 * sc * page.grid_zoom)
	var centre := Vector2(rect_size.x / 2, round(360.0 * sc))
	return [centre - Vector2(sz, sz) / 2, sz / 3.0]

func to_grid(p: Vector2) -> Vector2:
	if _3d():
		return page.view3d.grid_at(p)
	var g = _geom()
	return (p - g[0]) / g[1] - Vector2(0.5, 0.5)

func _placement(gp: Vector2) -> Vector2:
	if page.quantum:
		var q: float = float(max(page.quantum_divisor, 1))
		var off: Vector2 = page.quantum_offset
		var v := Vector2(round((gp.x - off.x) * q) / q + off.x, round((gp.y - off.y) * q) / q + off.y)
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
	var fs := int(clamp(cell * 0.27, 10, 40))
	if _font.size != fs:
		_font.size = fs
	if _3d():
		_draw_overlay(o, cell)
		_draw_bezier(o, cell)
		return
	_draw_2d(o, cell)
	_draw_bezier(o, cell)

# rounded rectangle (outline or filled), SSQE's note shape
func _rrect(r: Rect2, col: Color, filled: bool, width: float = 2.0, radius: float = -1.0):
	var sb = StyleBoxFlat.new()
	var rad := radius if radius >= 0 else r.size.x * 0.18
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	if filled:
		sb.bg_color = col
	else:
		sb.draw_center = false
		sb.border_color = col
		sb.set_border_width_all(int(max(width, 1)))
	draw_style_box(sb, r)

# The 2D view, drawn like Sound Space Quantum Editor's: a frame with guide
# lines, a grey grid, notes as rounded squares that fade in as they come.
func _draw_2d(o: Vector2, cell: float):
	var size := cell * 3.0
	var sc: float = page._scale
	var c := o + Vector2(size, size) / 2
	# frame + guide lines (SSQE's 390x400 frame around a 200px grid)
	var fr := Rect2(c + Vector2(-195, -193) * sc, Vector2(390, 400) * sc)
	draw_rect(fr, Color(0.22, 0.22, 0.24), false, 1.5)
	var bottom := rect_size.y
	draw_line(o + Vector2(0, size), Vector2(c.x - 430 * sc, bottom), Color(0.17, 0.17, 0.19), 3.0)
	draw_line(o + Vector2(size, size), Vector2(c.x + 410 * sc, bottom), Color(0.17, 0.17, 0.19), 3.0)
	# grid
	draw_rect(Rect2(o, Vector2(size, size)), Color(0.16, 0.16, 0.18))
	for k in range(1, 3):
		draw_line(o + Vector2(k * cell, 0), o + Vector2(k * cell, size), Color(0.11, 0.11, 0.12), 1.0)
		draw_line(o + Vector2(0, k * cell), o + Vector2(size, k * cell), Color(0.11, 0.11, 0.12), 1.0)
	if page.show_letters or page.show_numbers:
		for i in range(9):
			var r := Rect2(o + Vector2(i % 3, i / 3) * cell, Vector2(cell, cell))
			var t: String = KEYS[i] if not page.show_numbers else str(i + 1)
			var ts := _font.get_string_size(t)
			draw_string(_font, r.position + (r.size - ts) / 2 + Vector2(0, _font.get_ascent()), t, Color(0.3, 0.3, 0.32))
	if page.quantum and page.quantum_divisor > 1 and page.quantum_lines:
		var q: int = page.quantum_divisor
		var qc := Color(LILAC.r, LILAC.g, LILAC.b, 0.12)
		for k in range(-q, 3 * q + 1):
			if k % q == 0:
				continue
			var fx: float = (float(k) / q + page.quantum_offset.x + 0.5) * cell
			var fy: float = (float(k) / q + page.quantum_offset.y + 0.5) * cell
			if fx > 0.0 and fx < size:
				draw_line(o + Vector2(fx, 0), o + Vector2(fx, size), qc, 1.0)
			if fy > 0.0 and fy < size:
				draw_line(o + Vector2(0, fy), o + Vector2(size, fy), qc, 1.0)
	# hover
	var ns: float = cell * 0.78 * page.note_size_2d
	if _hover.x > -5:
		var hc: Vector2 = o + (_hover + Vector2(0.5, 0.5)) * cell
		_rrect(Rect2(hc - Vector2(ns, ns) / 2, Vector2(ns, ns)), Color(1, 1, 1, 0.25), false, 1.5)

	# notes: far ones first so near ones draw on top
	var now: float = page.time_ms
	var ar: float = page.approach_ms
	var notes: Array = page.project.notes
	var j: int = page.project.lower_bound(now - FADE_MS)
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
		var a := 1.0
		var p := 0.0
		if dt > 1.0:
			p = clamp(dt / max(ar, 1.0), 0.0, 1.0)
			a = 1.0 - p
		elif dt < -1.0:
			a = clamp(1.0 + dt / FADE_MS, 0.0, 1.0)
		var r := Rect2(center - Vector2(ns, ns) / 2, Vector2(ns, ns))
		_rrect(r, Color(col.r, col.g, col.b, 0.25 * a), true)
		_rrect(r, Color(col.r, col.g, col.b, a), false, max(2.0, cell * 0.035))
		if page.show_asq and dt > 1.0:
			var asz := ns * (1.0 + 2.2 * p)
			_rrect(Rect2(center - Vector2(asz, asz) / 2, Vector2(asz, asz)), Color(col.r, col.g, col.b, 0.75 * (1.0 - p)), false, 1.5)
		if page.is_selected(n[3]):
			var g := ns + 8
			_rrect(Rect2(center - Vector2(g, g) / 2, Vector2(g, g)), Color(1, 1, 1, max(a, 0.35)), false, 2.0)

	# autoplay cursor
	if page.show_cursor and not notes.empty():
		var cp = page.cursor_pos()
		if cp != null:
			var cc: Vector2 = o + (cp + Vector2(0.5, 0.5)) * cell
			var cs := cell * 0.2
			draw_rect(Rect2(cc - Vector2(cs, cs) / 2, Vector2(cs, cs)), Color(0.85, 0.85, 0.88, 0.75))
			draw_rect(Rect2(cc - Vector2(cs, cs) / 2, Vector2(cs, cs)), Color(1, 1, 1), false, 1.5)

# stored bezier nodes and the curve DRAW would follow (PATTERNS tab)
func _draw_bezier(o: Vector2, cell: float):
	var nodes: Array = page.bezier_nodes
	if nodes.size() < 2:
		return
	var pts := PoolVector2Array()
	for k in range(41):
		var gp: Vector2 = page.bezier_point(float(k) / 40.0)
		pts.append(o + (gp + Vector2(0.5, 0.5)) * cell)
	draw_polyline(pts, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), 2.0, true)
	for nd in nodes:
		var c: Vector2 = o + (Vector2(nd[0], nd[1]) + Vector2(0.5, 0.5)) * cell
		draw_circle(c, 5, ACCENT)

# Over the game view: only what the game doesn't draw (letters, quantum lines,
# hover, selection).
func _draw_overlay(o: Vector2, cell: float):
	var a: float = page.overlay_opacity
	var size := cell * 3.0
	if page.show_letters or page.show_numbers:
		for i in range(9):
			var r := Rect2(o + Vector2(i % 3, i / 3) * cell, Vector2(cell, cell))
			var t: String = KEYS[i] if not page.show_numbers else str(i + 1)
			var ts := _font.get_string_size(t)
			draw_string(_font, r.position + (r.size - ts) / 2 + Vector2(0, _font.get_ascent()), t, Color(1, 1, 1, 0.12 * a))
	if page.quantum and page.quantum_divisor > 1 and page.quantum_lines:
		var q: int = page.quantum_divisor
		var qc := Color(LILAC.r, LILAC.g, LILAC.b, 0.18 * a)
		for k in range(-q, 3 * q + 1):
			if k % q == 0:
				continue
			var fx: float = (float(k) / q + page.quantum_offset.x + 0.5) * cell
			var fy: float = (float(k) / q + page.quantum_offset.y + 0.5) * cell
			if fx > 0.0 and fx < size:
				draw_line(o + Vector2(fx, 0), o + Vector2(fx, size), qc, 1.0)
			if fy > 0.0 and fy < size:
				draw_line(o + Vector2(0, fy), o + Vector2(size, fy), qc, 1.0)
	var ns := cell * 0.9
	if _hover.x > -5:
		var hc: Vector2 = o + (_hover + Vector2(0.5, 0.5)) * cell
		draw_rect(Rect2(hc - Vector2(ns, ns) / 2, Vector2(ns, ns)), Color(1, 1, 1, 0.07 * a))
		draw_rect(Rect2(hc - Vector2(ns, ns) / 2, Vector2(ns, ns)), Color(1, 1, 1, 0.35 * a), false, 1.5)
	for n in page._at_current():
		if page.is_selected(n[3]):
			var c: Vector2 = o + (Vector2(n[0], n[1]) + Vector2(0.5, 0.5)) * cell
			draw_rect(Rect2(c - Vector2(ns, ns) / 2 - Vector2(3, 3), Vector2(ns + 6, ns + 6)), LILAC.lightened(0.3), false, 3.0)
