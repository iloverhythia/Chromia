extends Control
# The map editor's grid (SSQE's GuiGrid, ported from Sound Space Quantum
# Editor Plus's editor.js renderGrid): the notes coming up fading in on their
# cells, approach squares, grid numbers and letters, the note to be placed
# under the mouse, the bezier preview, the autoplay cursor and (3D Mode) the
# notes flying out from the middle. This control is the grid plus a cell all
# round (where the mouse still places notes on the edge cells); input is
# handled by the editor.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const RM = SSQEMap.RenderMode

var ed
var _bez_key := ""
var _bez_pts := []
var _sb := StyleBoxFlat.new()

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE

func col(i: int, a := 1.0) -> Color:
	return ed.track.col(i, a) if ed.track else Color(1, 1, 1, a)

func note_col(i, a := 1.0) -> Color:
	return ed.track.note_col(i, a)

func _squircle(r: Rect2, fill, stroke, w := 2.0):
	var s: Dictionary = ed.s
	if s.gridSquircles:
		var sb := _sb
		# GLVerts.Squircle: radius as a share of the size, at most half of it
		# (x1.5 so Godot's corner curve looks like SSQE+'s at the same setting)
		var mn: float = min(r.size.x, r.size.y)
		var rad := int(min(float(s.get("gridSquircleRadius", 0.125)) * mn * 1.5, mn / 2.0))
		sb.set_corner_radius_all(rad)
		sb.corner_detail = int(clamp(float(s.get("gridSquircleDetail", 8)), 1, 20))
		sb.anti_aliasing = true
		sb.draw_center = fill is Color
		sb.bg_color = fill if fill is Color else Color(0, 0, 0, 0)
		if stroke is Color:
			sb.border_color = stroke
			sb.set_border_width_all(int(max(1, round(w))))
		else:
			sb.set_border_width_all(0)
		draw_style_box(sb, r)
	else:
		if fill is Color:
			draw_rect(r, fill)
		if stroke is Color:
			draw_rect(r, stroke, false, w)

func _diamond(cx: float, cy: float, r: float, fill, stroke, w := 2.0):
	var pts := PoolVector2Array([Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy)])
	if fill is Color:
		draw_colored_polygon(pts, fill)
	if stroke is Color:
		pts.append(pts[0])
		draw_polyline(pts, stroke, w, true)

func _vline(x: float, y0: float, y1: float, c: Color):
	x = floor(x) + 0.5
	draw_line(Vector2(x, y0), Vector2(x, y1), c, 1.0)

func _hline(y: float, x0: float, x1: float, c: Color):
	y = floor(y) + 0.5
	draw_line(Vector2(x0, y), Vector2(x1, y), c, 1.0)

func _draw():
	if ed == null or ed.map == null:
		return
	var s: Dictionary = ed.s
	var map = ed.map
	# grid rect in this control's coordinates
	var G: Rect2 = Rect2(ed.GRID.position - rect_position, ed.GRID.size)
	var cell: float = G.size.x / 3.0
	var note_size: float = cell * 0.75 * clamp(float(s.gridNoteSize) / 100.0, 0.25, 2.0)
	var preview_size := cell * 0.65
	var note_gap := (cell - note_size) / 2
	var preview_gap := (cell - preview_size) / 2
	var t: float = ed.current_time()
	var ar := (float(s.approachRate) + 1.0) / 10.0
	var max_ms := t + 1000.0 / ar
	var m: Vector2 = ed.mouse - rect_position
	var text_scale := G.size.x / 300.0
	var mode3d: bool = s.mode3D
	var gm := 1.0
	if mode3d:
		draw_rect(G, Color(0, 0, 0))
		gm = clamp(float(s.grid3DOpacity), 0, 255) / 255.0

	# background, outline and divisor lines
	draw_rect(G, Color8(39, 39, 39, int(float(s.gridOpacity) * gm)))
	draw_rect(Rect2(G.position + Vector2(0.5, 0.5), G.size - Vector2(1, 1)), Color(52 / 255.0, 52 / 255.0, 52 / 255.0, gm), false, 1.0)
	var dark := Color(13 / 255.0, 13 / 255.0, 13 / 255.0, gm)
	var lc := Color(52 / 255.0, 52 / 255.0, 52 / 255.0, gm)
	for i in range(1, 3):
		_vline(G.position.x + G.size.x / 3 * i, G.position.y, G.end.y, dark)
		_hline(G.position.y + G.size.y / 3 * i, G.position.x, G.end.x, dark)
	if s.oldQuantumSnap:
		var divisor: float = float(s.quantumSnapping) + 3 if s.quantumGridLines else 3.0
		var offset := 0.5 if int(round(divisor)) % 2 == 0 else 1.0
		var i := int(2 * offset)
		while i <= divisor:
			var x := G.position.x + G.size.x / divisor * (i - offset)
			var y := G.position.y + G.size.y / divisor * (i - offset)
			_vline(x, G.position.y, G.end.y, lc)
			_hline(y, G.position.x, G.end.x, lc)
			i += 1
	else:
		var inc: float = 2.0 / (float(s.quantumSnapping) + 2.0) if s.quantumGridLines else 1.0
		var gap := (1.0 - inc) / 2.0
		var gap_inc := floor(gap / inc) * inc
		var x := fmod(float(s.quantumXOffset) - 1.0, inc) - inc
		while x < 3:
			var pos := G.position.x + (x - gap_inc + gap) * cell
			if pos >= G.position.x - 0.001 and pos <= G.end.x + 0.001:
				_vline(pos, G.position.y, G.end.y, lc)
			x += inc
		var y := fmod(float(s.quantumYOffset) - 1.0, inc) - inc
		while y < 3:
			var pos2 := G.position.y + (y - gap_inc + gap) * cell
			if pos2 >= G.position.y - 0.001 and pos2 <= G.end.y + 0.001:
				_hline(pos2, G.position.x, G.end.x, lc)
			y += inc

	# grid letters
	if s.gridLetters:
		var keys: Array = SSQESettings.NUMPAD_KEYS if s.numpad else SSQESettings.GRID_KEYS
		var f: DynamicFont = ed.font(int(round(38 * text_scale * 0.78)), true)
		for i in range(keys.size()):
			var gx := i % 3
			var gy := i / 3
			if map.render_mode != RM.NOTES and map.object_mode != SSQEMap.OBJ_NOTE and not ed.object_key_exists(map.object_mode, 2 - gx, 2 - gy):
				continue
			var name := SSQESettings.key_name(keys[i])
			var sz := f.get_string_size(name)
			draw_string(f, Vector2(G.position.x + gx * cell + cell / 2 - sz.x / 2, G.position.y + gy * cell + cell / 2 - sz.y / 2 + f.get_ascent()), name, Color(52 / 255.0, 52 / 255.0, 52 / 255.0, gm))

	# notes
	var notes = map.notes
	var r: Array = notes.search_range(t, max_ms)
	var low: int = r[0]
	var high: int = r[1]
	var is_special: bool = map.render_mode == RM.SPECIAL
	var show_notes: bool = ed.render_notes()
	ed.hovering_xy = null
	var drawn := []
	var depth := 5.0
	var passed_ms := 200.0
	var window3d: float = max(1.0, max_ms - t)
	var gc := G.position + G.size / 2
	if mode3d and s.mode3DHitEffect:
		var pr: Array = notes.search_range(t - passed_ms, t)
		for i in range(pr[0], low):
			var n = notes.items[i]
			var age: float = clamp((t - n.ms) / passed_ms, 0, 1)
			var pl := _place3d(n, 1 + age * 0.6, G, cell, note_size, gc)
			drawn.append([n, i, pl.x, pl.y, pl.z, 1.0 - age])
	for i in range(low, high):
		var n = notes.items[i]
		var x: float = G.position.x + (2 - n.x) * cell + note_gap
		var y: float = G.position.y + (2 - n.y) * cell + note_gap
		var size := note_size
		var progress: float = 1.0 - min(1.0, (n.ms - t) * ar / 750.0)
		if is_special and n.enable_easing:
			progress = SSQEMap.ease_value(0, 1, progress, n.style, n.direction)
		else:
			progress = min(1.0, progress * progress)
		progress = clamp(progress, 0, 1)
		if mode3d:
			var z: float = clamp((n.ms - t) / window3d, 0, 1)
			var pl2 := _place3d(n, 1.0 / (1.0 + z * depth), G, cell, note_size, gc)
			x = pl2.x
			y = pl2.y
			size = pl2.z
		elif ed.can_select() and show_notes and abs(m.x - note_size / 2 - x) <= note_size / 2 and abs(m.y - note_size / 2 - y) <= note_size / 2:
			if ed.hovering_xy == null:
				ed.hovering_xy = n
		drawn.append([n, i, x, y, size, progress])
	if mode3d:
		drawn.sort_custom(self, "_smaller_first")
	for d in drawn:
		var c = d[0].by_color if d[0].by_color != null else d[1]
		var lw := max(1.0, 2.0 * d[4] / note_size) if mode3d else 2.0
		var nc: Color = note_col(c, 1.0)
		var p: float = clamp(d[5], 0, 1)
		_squircle(Rect2(d[2], d[3], d[4], d[4]), Color(nc.r, nc.g, nc.b, 0.15 * p), Color(nc.r, nc.g, nc.b, p), lw)
		if s.approachSquares and not mode3d:
			var asz := 4 + note_size + note_size * (1 - p) * 2 + 0.5
			_squircle(Rect2(d[2] - asz / 2 + note_size / 2, d[3] - asz / 2 + note_size / 2, asz, asz), null, Color(nc.r, nc.g, nc.b, p), max(1, asz * 0.0125))
	if show_notes:
		for d in drawn:
			if d[0].selected:
				_squircle(Rect2(d[2] - 4, d[3] - 4, d[4] + 8, d[4] + 8), null, col(6, d[5]), 2)
			if ed.hovering_xy == d[0]:
				_squircle(Rect2(d[2] - 4, d[3] - 4, d[4] + 8, d[4] + 8), null, col(5, 0.25), 2)
	if s.gridNumbers:
		for d in drawn:
			var f2: DynamicFont = ed.font(int(round(28 * text_scale * d[4] / note_size * 0.78)))
			var txt: String = ed.track.comma(d[1] + 1)
			var ts := f2.get_string_size(txt)
			draw_string(f2, Vector2(d[2] + d[4] / 2 - ts.x / 2, d[3] + d[4] / 2 - ts.y / 2 + f2.get_ascent()), txt, col(4, d[5]))

	# extra objects
	if is_special:
		if map.object_mode != SSQEMap.OBJ_NOTE:
			ed.hovering_xy = null
		_draw_special(t, max_ms, ar, G, cell, m)

	# place preview
	if typeof(ed.hovering_cell) != TYPE_NIL and ed.hovering_xy == null and ed.can_place() and show_notes:
		var hc: Vector2 = ed.hovering_cell
		var px: float = G.position.x + (2 - hc.x) * cell + preview_gap
		var py: float = G.position.y + (2 - hc.y) * cell + preview_gap
		_squircle(Rect2(px, py, preview_size, preview_size), col(9, 0.125), col(9, 0.09375), 2)

	# bezier preview
	var nodes := []
	for i in notes.bezier_nodes:
		if i < notes.items.size():
			nodes.append(notes.items[i])
	if nodes.size() > 1:
		var div := int(float(s.bezierDivisor) + 0.5)
		var key := "%d|%s|%s" % [div, str(s.curveBezier), str(G)]
		for n in nodes:
			key += "|%s,%s,%d,%d" % [str(n.x), str(n.y), n.ms, 1 if n.anchored else 0]
		if key != _bez_key:
			_bez_key = key
			_bez_pts = []
			if div > 0:
				for segment in SSQEMap.bezier_segments(nodes, div, bool(s.curveBezier)):
					for n in segment:
						_bez_pts.append(Vector2(G.position.x + (2 - n.x) * cell + preview_gap, G.position.y + (2 - n.y) * cell + preview_gap))
		for p in _bez_pts:
			_squircle(Rect2(p.x, p.y, preview_size, preview_size), col(2, 0.125), col(2, 0.09375), 2)
		if _bez_pts.size() > 1:
			var line := PoolVector2Array()
			for p in _bez_pts:
				line.append(p + Vector2(preview_size, preview_size) / 2)
			draw_polyline(line, Color(1, 1, 1), 1.0, true)

	# autoplay cursor
	if s.autoplay:
		_draw_autoplay(low, t, G, cell)

static func _smaller_first(a, b) -> bool:
	return a[4] < b[4]

# 3D Mode: notes in perspective, flying out from the middle towards their cell
func _place3d(n, scale: float, G: Rect2, cell: float, note_size: float, gc: Vector2) -> Vector3:
	var size := note_size * scale
	var cx: float = gc.x + (G.position.x + (2 - n.x + 0.5) * cell - gc.x) * scale
	var cy: float = gc.y + (G.position.y + (2 - n.y + 0.5) * cell - gc.y) * scale
	return Vector3(cx - size / 2, cy - size / 2, size)

func _draw_special(t: float, max_ms: float, ar: float, G: Rect2, cell: float, m: Vector2):
	var map = ed.map
	var s: Dictionary = ed.s
	var objects = map.special_objects
	var r: Array = objects.search_range(t, max_ms)
	var check_id: bool = map.object_mode != SSQEMap.OBJ_DISABLED
	var mine_size := cell * 0.6
	var mine_gap := (cell - mine_size) / 2
	var c5 := col(10)
	for i in range(0, r[1]):
		var o = objects.items[i]
		if o.ms < t:
			continue
		if check_id and o.id != map.object_mode:
			continue
		var progress: float = min(1.0, pow(1.0 - min(1.0, (o.ms - t) * ar / 750.0), 2))
		if o.id == 14:
			var x: float = G.position.x + (2 - o.x) * cell + mine_gap
			var y: float = G.position.y + (2 - o.y) * cell + mine_gap
			var cx := x + mine_size / 2
			var cy := y + mine_size / 2
			if ed.can_select() and abs(m.x - cx) <= mine_size / 2 and abs(m.y - cy) <= mine_size / 2 and ed.hovering_xy == null:
				ed.hovering_xy = o
			_diamond(cx, cy, mine_size / 2, col(8, 0.15 * progress), col(8, progress))
			if s.approachSquares:
				var size := 4 + mine_size + mine_size * (1 - progress) * 2 + 0.5
				_diamond(cx, cy, size / 2, null, col(8, progress), max(1, size * 0.0125))
			if o.selected:
				_diamond(cx, cy, mine_size / 2 + 4, null, col(6, progress))
			if ed.hovering_xy == o:
				_diamond(cx, cy, mine_size / 2 + 4, null, col(5, 0.25))
		elif o.id == 12:
			var cc := Color(c5.r, c5.g, c5.b, progress)
			draw_rect(Rect2(G.position - Vector2(5, 5), G.size + Vector2(10, 10)), cc, false, 3)
			if s.approachSquares:
				var size2 := 4 + G.size.x + G.size.x * (1 - progress) + 0.5
				draw_rect(Rect2(G.position + G.size / 2 - Vector2(size2, size2) / 2, Vector2(size2, size2)), cc, false, max(1, size2 * 0.0075))
		elif o.id == 13:
			var ctr := G.position + G.size / 2
			var ang: float = o.direction * PI / 2
			var cc2 := Color(c5.r, c5.g, c5.b, progress)
			var hw := G.size.x / 2 + 5
			var corners := [Vector2(-hw, -hw), Vector2(hw, -hw), Vector2(hw, hw), Vector2(-hw, hw), Vector2(-hw, -hw)]
			var pts := PoolVector2Array()
			for cpt in corners:
				pts.append(ctr + cpt.rotated(ang))
			draw_polyline(pts, cc2, 3, true)
			draw_line(ctr + Vector2(-G.size.x / 2 + 10, -G.size.y / 2 + 13).rotated(ang), ctr + Vector2(G.size.x / 2 - 10, -G.size.y / 2 + 13).rotated(ang), cc2, 6, true)
			for oy in [-G.size.y / 5, G.size.y / 5]:
				var tri := PoolVector2Array()
				var rr := G.size.x / 10
				for k in range(4):
					var a := deg2rad(-90 + k * 120)
					tri.append(ctr + Vector2(cos(a) * rr, oy + sin(a) * rr).rotated(ang))
				draw_polyline(tri, cc2, 8, true)

# the autoplay cursor
func _draw_autoplay(low: int, t: float, G: Rect2, cell: float):
	var notes: Array = ed.map.notes.items
	var def := Vector3(1, 1, 0) # x, y, ms
	var index := int(max(0, low - 1))
	var last_far := _xyms(notes[index - 1]) if index > 0 and index < notes.size() else def
	var last := _xyms(notes[index]) if index < notes.size() else def
	var nxt := _xyms(notes[index + 1]) if index + 1 < notes.size() else last
	var next_far := _xyms(notes[index + 2]) if index + 2 < notes.size() else nxt
	if t > nxt.z:
		last_far = last
		last = nxt
	if t < last.z:
		next_far = nxt
		nxt = last
	var diff := nxt.z - last.z
	var p := 1.0 if diff == 0 else (t - last.z) / diff
	var x := cell / 2 + G.position.x
	var y := cell / 2 + G.position.y
	if ed.s.smoothAutoplay:
		x += (2 - _cr(last_far.x, last.x, nxt.x, next_far.x, p)) * cell
		y += (2 - _cr(last_far.y, last.y, nxt.y, next_far.y, p)) * cell
	else:
		p = sin(p * PI / 2)
		var lx := (2 - last.x) * cell
		var ly := (2 - last.y) * cell
		var nx := (2 - nxt.x) * cell
		var ny := (2 - nxt.y) * cell
		x += lx + (nx - lx) * p
		y += ly + (ny - ly) * p
	var width := sin(p * PI) * 8 + 16
	width *= G.size.x / 300.0
	draw_rect(Rect2(x - width / 2, y - width / 2, width, width), Color(1, 1, 1, 0.25))
	draw_rect(Rect2(x - width / 2, y - width / 2, width, width), Color(1, 1, 1, 1), false, max(1, width * 0.075))

static func _xyms(n) -> Vector3:
	return Vector3(n.x, n.y, n.ms)

static func _cr(a: float, b: float, c: float, d: float, p: float) -> float:
	return 0.5 * (2 * b + (-a + c) * p + (2 * a - 5 * b + 4 * c - d) * p * p + (-a + 3 * b - 3 * c + d) * p * p * p)
