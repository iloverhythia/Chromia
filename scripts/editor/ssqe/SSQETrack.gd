extends Control
# The map editor's track (SSQE's GuiTrack, ported from Sound Space Quantum
# Editor Plus's editor.js renderTrack): the notes or objects along the song,
# with their position on a mini grid, beat ticks for the beat divisor, timing
# points, the waveform and the labels under it. Input is handled by the editor
# (this only draws); the control is twice the track's height, so the labels
# and timing point boxes under it are drawn here too.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const RM = SSQEMap.RenderMode

var ed

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE

# palette: [color1, color2, color3, color4, white, green, blue, light grey, red, grey, color5]
func col(i: int, a := 1.0) -> Color:
	var s: Dictionary = ed.s
	match i:
		0: return SSQESettings.color(s, "color1", a)
		1: return SSQESettings.color(s, "color2", a)
		2: return SSQESettings.color(s, "color3", a)
		3: return SSQESettings.color(s, "color4", a)
		4: return Color(1, 1, 1, a)
		5: return Color8(0, 255, 64, int(a * 255))
		6: return Color8(0, 128, 255, int(a * 255))
		7: return Color8(191, 191, 191, int(a * 255))
		8: return Color8(255, 0, 0, int(a * 255))
		9: return Color8(128, 128, 128, int(a * 255))
		10: return SSQESettings.color(s, "color5", a)
	return Color(1, 1, 1, a)

# the notes' colours: SSQE+'s own list (Settings > Colors) or the game's colour set
func _note_cols() -> Array:
	var s: Dictionary = ed.s
	if s.get("customNoteColors", false) and s.get("noteColors") is Array and not s.noteColors.empty():
		var out := []
		for c in s.noteColors:
			if c is Array and c.size() >= 3:
				out.append(Color8(int(c[0]), int(c[1]), int(c[2])))
		if not out.empty():
			return out
	var cols: Array = Rhythia.selected_colorset.colors if Rhythia.selected_colorset else []
	return cols if not cols.empty() else [Color8(255, 0, 255), Color8(0, 255, 200)]

var _cols_frame := -1
var _cols_cache: Array = []

func note_col(i, a := 1.0) -> Color:
	# worked out once a frame (called for every object drawn)
	var fr := Engine.get_frames_drawn()
	if fr != _cols_frame:
		_cols_frame = fr
		_cols_cache = _note_cols()
	var cols: Array = _cols_cache
	var c: Color = cols[int(i) % int(max(cols.size(), 1))] if not cols.empty() else Color(1, 1, 1)
	return Color(c.r, c.g, c.b, a)

func _line(a: Vector2, b: Vector2, c: Color, w := 1.0):
	if a.x == b.x:
		a.x = floor(a.x) + 0.5
		b.x = a.x
	draw_line(a, b, c, w)

# pts plus a rectangle's outline as 4 line segments (for draw_multiline)
static func _outline_pts(pts: PoolVector2Array, x: float, y: float, w: float, h: float) -> PoolVector2Array:
	var a := Vector2(x, y)
	var b := Vector2(x + w, y)
	var d := Vector2(x + w, y + h)
	var e := Vector2(x, y + h)
	pts.append(a); pts.append(b)
	pts.append(b); pts.append(d)
	pts.append(d); pts.append(e)
	pts.append(e); pts.append(a)
	return pts

func _stroke_box(x: float, y: float, w: float, h: float, c: Color):
	draw_rect(Rect2(x + 0.5, y + 0.5, w - 1, h - 1), c, false, 1.0)

func _diamond(cx: float, cy: float, r: float, fill, stroke, w := 2.0):
	var pts := PoolVector2Array([Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy)])
	if fill is Color:
		draw_colored_polygon(pts, fill)
	if stroke is Color:
		pts.append(pts[0])
		draw_polyline(pts, stroke, w, true)

static func comma(n: int) -> String:
	var neg := n < 0
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out

func _draw():
	if ed == null or ed.map == null:
		return
	var s: Dictionary = ed.s
	var map = ed.map
	var H: float = rect_size.y / 2
	var W: float = rect_size.x
	var note_size: float = H * 0.52
	var cell_gap: float = H * 0.14
	var ms_to_px: float = ed.ms_to_px()
	var px_to_ms: float = ed.px_to_ms()
	var current_time: float = ed.current_time()
	var total_time: float = ed.total_time()
	var current_pos := current_time * ms_to_px
	var cursor_pos: float = W * float(s.cursorPos) / 100.0
	var end_pos := cursor_pos - current_pos + total_time * ms_to_px + 1
	var min_ms := (-cursor_pos - note_size) * px_to_ms + current_time
	var max_ms := (W - cursor_pos) * px_to_ms + current_time
	var base_x := cursor_pos - current_pos
	ed.track_start_rel = max(0.0, (-cursor_pos * px_to_ms + current_time) / max(total_time, 1))
	ed.track_end_rel = min(1.0, ((W - cursor_pos) * px_to_ms + current_time) / max(total_time, 1))

	# background
	draw_rect(Rect2(0, 0, W, H), Color8(39, 39, 39, int(s.trackOpacity)))
	_stroke_box(0, 0, W, H, Color8(52, 52, 52))

	# waveform
	if s.waveform and ed.waveform:
		_draw_waveform(ed.waveform, base_x, ms_to_px, min_ms, max_ms, H)

	ed.hovering_object = null
	ed.hovering_duration = null
	var mx: float = ed.mouse.x
	var my: float = ed.mouse.y
	var labels := []
	var last_text := -1e9

	if ed.selecting:
		var xs: float = base_x + ed.select_ms_start * ms_to_px
		var xe: float = base_x + ed.select_ms_end * ms_to_px
		draw_rect(Rect2(min(xs, xe), 0, abs(xe - xs), H), col(5, 0.04))

	var dragging: bool = not ed.dragging_objects.empty() and ed.dragging_objects[0].id != 1
	var cell := note_size * 0.3
	var mark := note_size * 0.2

	if ed.render_notes():
		var notes = map.notes
		var r: Array = notes.search_range(min_ms, max_ms)
		var low: int = r[0]
		var high: int = r[1]
		var items: Array = notes.items
		for i in range(low, high):
			var x: float = base_x + items[i].ms * ms_to_px
			if not dragging and mx > x and mx < x + note_size and my > cell_gap and my < cell_gap + note_size:
				if ed.hovering_object == null:
					ed.hovering_object = items[i]
		var last_box := -1e9
		var any_hover: bool = ed.hovering_object != null
		# zoomed out, notes overlap: the small 3x3 grid inside a box is only
		# drawn when the box has room to show, and labels need room to be read
		# (every note's box, grid and label used to be drawn on top of each
		# other: 60 ms a frame zoomed out on a 2,000 note map)
		var box_gap: float = max(1.0, note_size * 0.35)
		var lf: DynamicFont = ed.font(int(round(H / 4 * 0.95)))
		var label_gap: float = max(8.0, lf.get_string_size("Note 00,000").x + 6.0) # (labels side by side, not on top of each other)
		var line_pts_on := PoolVector2Array()
		var line_pts_dim := PoolVector2Array()
		# a note's box and its 3x3 mini grid are two ready-made outlines, each
		# drawn with one call where the note is: an outlined draw_rect is slow
		# (10 a note were 50 ms a frame zoomed out)
		var tmpl_box := PoolVector2Array()
		tmpl_box = _outline_pts(tmpl_box, 0.5, 0.5, note_size - 1, note_size - 1)
		var tmpl_cells := PoolVector2Array()
		for k in range(9):
			tmpl_cells = _outline_pts(tmpl_cells, (2 - k % 3) * cell + note_size * 0.1 + 0.5, (k / 3) * cell + note_size * 0.1 + 0.5, mark - 1, mark - 1)
		var cols: Array = _note_cols()
		var ncols: int = cols.size()
		var last_drawn := -1e9
		for i in range(low, high):
			var n = items[i]
			var is_hovering: bool = ed.hovering_object == n
			var x: float = base_x + n.ms * ms_to_px
			# several notes on one pixel: only the first is drawn (selected and
			# hovered ones always are)
			if x - last_drawn < 1.0 and not is_hovering and not n.selected:
				continue
			last_drawn = x
			var a: float = 0.35 if n.ms < current_time - 1 else 1.0
			var c0: Color = cols[i % ncols]
			var c := Color(c0.r, c0.g, c0.b, a)
			var roomy: bool = x - last_box >= box_gap
			var spacious: bool = x - last_box >= note_size # (the mini grid only shows on a box of its own)
			if roomy or is_hovering or n.selected:
				draw_rect(Rect2(x, cell_gap, note_size, note_size), Color(c.r, c.g, c.b, a / 20.0))
				draw_set_transform(Vector2(x, cell_gap), 0, Vector2.ONE)
				draw_multiline(tmpl_box, c)
				if spacious or is_hovering:
					draw_multiline(tmpl_cells, Color(c.r, c.g, c.b, a * 0.45))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				last_box = x
			draw_rect(Rect2(x + (2 - n.x) * cell + note_size * 0.1, cell_gap + (2 - n.y) * cell + note_size * 0.1, mark, mark), c)
			# the line under each note: all drawn at once below
			var lx: float = floor(x) + 0.5
			var lpts: PoolVector2Array = line_pts_on if (a >= 1.0 and (not any_hover or is_hovering)) else line_pts_dim
			lpts.append(Vector2(lx, H + 2))
			lpts.append(Vector2(lx, H * 1.4))
			if a >= 1.0 and (not any_hover or is_hovering):
				line_pts_on = lpts
			else:
				line_pts_dim = lpts
			if is_hovering:
				_stroke_box(x - 4, cell_gap - 4, note_size + 8, note_size + 8, col(5))
			elif n.selected:
				if dragging:
					var dx: float = base_x + n.drag_start_ms * ms_to_px
					_line(Vector2(dx, 0), Vector2(dx, H), col(7))
				else:
					_stroke_box(x - 4, cell_gap - 4, note_size + 8, note_size + 8, col(6))
			is_hovering = is_hovering or (dragging and n.selected)
			if x - label_gap > last_text or is_hovering:
				labels.append([x + 3, "Note " + comma(i + 1), comma(n.ms) + "ms", is_hovering])
				last_text = x
		if line_pts_dim.size() > 0:
			draw_multiline(line_pts_dim, col(4, 0.35))
		if line_pts_on.size() > 0:
			draw_multiline(line_pts_on, col(4, 1.0))
	else:
		var list = map.vfx_objects if map.render_mode == RM.VFX else map.special_objects
		var check_id: bool = map.render_mode == RM.SPECIAL and map.object_mode != SSQEMap.OBJ_DISABLED
		var indices := {}
		for o in list.items:
			if o.duration + o.ms < min_ms:
				continue
			if o.ms > max_ms:
				break
			if check_id and o.id != map.object_mode:
				continue
			var x: float = base_x + o.ms * ms_to_px
			if mx > x and mx < x + note_size and my > cell_gap and my < cell_gap + note_size and ed.hovering_object == null:
				ed.hovering_object = o
		var any_hover2: bool = ed.hovering_object != null
		for i in range(list.items.size()):
			var o = list.items[i]
			indices[o.id] = int(indices.get(o.id, 0)) + 1
			if o.duration + o.ms < min_ms:
				continue
			if o.ms > max_ms:
				break
			if check_id and o.id != map.object_mode:
				continue
			var is_hov: bool = ed.hovering_object == o or ed.hovering_duration == o
			var x: float = base_x + o.ms * ms_to_px
			var a: float = 0.35 if o.ms < current_time - 1 else 1.0
			var ci: int = (indices[o.id] - 1) if check_id else i
			var cc := note_col(ci, a)
			var cx := x + note_size / 2
			var cy := cell_gap + note_size / 2
			if o.has_duration:
				var width: float = o.duration * ms_to_px
				_line(Vector2(x + note_size, cy), Vector2(x + note_size + max(width - note_size, 0), cy), cc, 4)
				_diamond(x + width, cy, note_size / 4, cc, null)
				if abs(mx - x - width) < note_size / 4 and abs(my - cy) < note_size / 4 and ed.hovering_duration == null:
					ed.hovering_duration = o
				if ed.hovering_duration == o:
					_diamond(x + width, cy, note_size / 4 + 4, null, col(5), 1)
				elif ed.dragging_duration == o:
					_diamond(x + width, cy, note_size / 4 + 4, null, col(6), 1)
			draw_circle(Vector2(cx, cy), note_size / 2, Color(cc.r, cc.g, cc.b, a / 20.0))
			draw_arc(Vector2(cx, cy), note_size / 2, 0, TAU, 32, cc, 2, true)
			_draw_object_icon(o, Vector2(cx, cy), note_size * 0.38, cc)
			_line(Vector2(x + 0.5, H + 2), Vector2(x + 0.5, H * 1.4), col(4, a if (not any_hover2 or is_hov) else 0.35))
			if is_hov:
				draw_arc(Vector2(cx, cy), note_size / 2 + 4, 0, TAU, 32, col(5), 1, true)
			elif o.selected:
				if dragging:
					var dx2: float = base_x + o.drag_start_ms * ms_to_px
					_line(Vector2(dx2, 0), Vector2(dx2, H), col(7))
				else:
					draw_arc(Vector2(cx, cy), note_size / 2 + 4, 0, TAU, 32, col(6), 1, true)
			is_hov = is_hov or (dragging and o.selected)
			if x - 8 > last_text or is_hov:
				labels.append([x + 3, "%s %s" % [o.name, comma(indices[o.id])], comma(o.ms) + "ms", is_hov])
				last_text = x

	# timing points and beat ticks
	var beat_div: float = map.beat_divisor + 1.0
	var multiplier := 1.0 if fmod(beat_div, 1.0) == 0 else 1.0 / fmod(beat_div, 1.0)
	var divisor := int(round(beat_div * multiplier))
	var multiple_of_two := divisor % 2 == 0
	var divisor_reset := int((divisor - 1) / 2) * 2
	var tick_gap := H - note_size - cell_gap
	var points: Array = map.timing_points
	var bpm_labels := []
	for i in range(points.size()):
		var point = points[i]
		if point.bpm <= 0:
			continue
		var start_x: float = base_x + point.ms * ms_to_px
		var ms_inc: float = 60000.0 / point.bpm * multiplier
		var half_inc := ms_inc / 2
		var sub_inc := ms_inc / divisor
		if mx > start_x and mx < start_x + H and my > H and my < H * 2 and ed.hovering_object == null:
			ed.hovering_object = point
		if point.ms <= total_time:
			var next_ms: float = min(points[i + 1].ms, total_time) if i + 1 < points.size() else total_time
			var total_ms: float = next_ms - point.ms
			var vis_start: float = max(0, min_ms - point.ms)
			var vis_end: float = min(total_ms, max_ms - point.ms)
			if vis_end > vis_start - ms_inc:
				var num_beats := int(total_ms / ms_inc)
				var num_half := int(total_ms / half_inc - num_beats) if multiple_of_two else 0
				var num_sub := int(total_ms / sub_inc - num_beats - num_half)
				var j0 := int(max(0, floor(vis_start / ms_inc) - 1))
				var j1 := int(min(num_beats, ceil(vis_end / ms_inc) + 1))
				for j in range(j0, j1):
					var x := start_x + ms_inc * (j + 1) * ms_to_px
					_line(Vector2(x, H), Vector2(x, H - tick_gap), col(1))
				for j in range(j0, min(num_half, j1)):
					var x2 := start_x + (ms_inc * j + half_inc) * ms_to_px
					_line(Vector2(x2, H - 3 * tick_gap / 5), Vector2(x2, H), col(2))
				if num_sub > 0 and divisor_reset > 0:
					# (the original's instancing loop: tick j sits at sub_inc * j + an increment that grows by
					# sub_inc at every reset and at every half beat; worked out directly so only the ticks on
					# screen are visited)
					var d2 := divisor / 2 - 1
					var lo := 0
					var hi := num_sub
					while lo < hi:
						var mid := (lo + hi) >> 1
						if start_x + _sub_tick(mid, sub_inc, divisor_reset, d2, multiple_of_two) * ms_to_px < 0:
							lo = mid + 1
						else:
							hi = mid
					for j in range(lo, num_sub):
						var x3 := start_x + _sub_tick(j, sub_inc, divisor_reset, d2, multiple_of_two) * ms_to_px
						if x3 > W:
							break
						_line(Vector2(x3, H - 3 * tick_gap / 10), Vector2(x3, H), col(0))
		_line(Vector2(start_x, 0), Vector2(start_x, H * 1.95), col(8))
		if ed.hovering_object == point:
			_stroke_box(start_x - 4, H, H, H, col(5))
		elif map.selected_point == point:
			_stroke_box(start_x - 4, H, H, H, col(6))
		bpm_labels.append([start_x + 3, SSQEMap.fmt(stepify(point.bpm, 0.001)) + " BPM", comma(point.ms) + "ms"])

	# song start, song end, cursor
	_line(Vector2(base_x, 0), Vector2(base_x, H), col(1))
	_line(Vector2(end_pos, 0), Vector2(end_pos, H), col(8))
	_line(Vector2(cursor_pos, 0), Vector2(cursor_pos, H), col(4, 0.75))
	if ed.selecting:
		var a1: float = base_x + ed.select_ms_start * ms_to_px
		var a2: float = base_x + ed.select_ms_end * ms_to_px
		_line(Vector2(a1, 0), Vector2(a1, H), col(5))
		_line(Vector2(a2, 0), Vector2(a2, H), col(5))

	# labels (GuiTrack.PostRender)
	var f: DynamicFont = ed.font(int(round(H / 4 * 0.95)))
	var any_label_hover := false
	for l in labels:
		if l[3]:
			any_label_hover = true
			break
	var asc := f.get_ascent()
	for l in labels:
		var al := 0.2 if (any_label_hover and not l[3]) else 1.0
		draw_string(f, Vector2(l[0], H + asc), l[1], col(0, al))
		draw_string(f, Vector2(l[0], H * 1.2 + asc), l[2], col(1, al))
	for l in bpm_labels:
		draw_string(f, Vector2(l[0], H + H / 2 + asc), l[1], col(0))
		draw_string(f, Vector2(l[0], H * 1.2 + H / 2 + asc), l[2], col(1))

# where sub tick j is, in ms after its timing point
static func _sub_tick(j: int, sub_inc: float, reset: int, d2: int, two: bool) -> float:
	var count := 1 + j / reset
	if two and j >= d2:
		count += (j - d2) / reset + 1
	return sub_inc * j + sub_inc * count

# the extra objects' symbols (Sprites.png in SSQE)
func _draw_object_icon(o, c: Vector2, r: float, color: Color):
	match o.id:
		12: # beat: a circle
			draw_arc(c, r * 0.7, 0, TAU, 24, color, 2, true)
		13: # glide: an arrow
			var ang: float = [-PI / 2, 0, PI / 2, PI][clamp(o.direction, 0, 3)]
			var d := Vector2(cos(ang), sin(ang))
			var p := Vector2(-d.y, d.x)
			draw_line(c - d * r * 0.7, c + d * r * 0.7, color, 2, true)
			draw_line(c + d * r * 0.7, c + d * r * 0.2 + p * r * 0.45, color, 2, true)
			draw_line(c + d * r * 0.7, c + d * r * 0.2 - p * r * 0.45, color, 2, true)
		14: # mine: a diamond
			_diamond(c.x, c.y, r * 0.75, null, color, 2)
		15: # lyric: "T"
			draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, -r * 0.6), color, 2, true)
			draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.7), color, 2, true)
		16: # fever: a flame-ish triangle
			draw_colored_polygon(PoolVector2Array([c + Vector2(0, -r * 0.8), c + Vector2(r * 0.6, r * 0.6), c + Vector2(-r * 0.6, r * 0.6)]), Color(color.r, color.g, color.b, color.a * 0.6))
		_:
			draw_circle(c, r * 0.25, color)

# The waveform's points are worked out once per zoom level (for the whole
# song, at most ~2 a pixel), in pieces of WAVE_CHUNK points, and moved with
# the scroll: only the pieces on screen are drawn. Working them out every
# frame was slow zoomed out.
const WAVE_CHUNK := 512
var _wave_key := ""
var _wave_cache := {} # piece index -> PoolVector2Array (for _wave_key)

func _draw_waveform(wave, base_x: float, ms_to_px: float, min_ms: float, max_ms: float, H: float):
	var offset: float = ed.music_offset() - 15.0
	var step_ms: float = wave.res * 1000.0
	var first := int(max(0, floor((min_ms - offset) / step_ms) - 1))
	var last := int(min(wave.count - 1, ceil((max_ms - offset) / step_ms) + 1))
	if last <= first:
		return
	var classic: bool = ed.s.classicWaveform
	# at most ~2 points a pixel, from the zoom alone: worked out from what's on
	# screen it could flip between two values while playing, and every flip
	# made the whole song's waveform again (frames of 100+ ms)
	var stride := 1
	while step_ms * ms_to_px * stride < 0.5:
		stride *= 2
	var key := "%f|%f|%f|%d|%s|%d" % [step_ms, ms_to_px, H, stride, str(classic), wave.count]
	if key != _wave_key:
		_wave_key = key
		_wave_cache = {}
	# only the pieces on screen are made (and kept while the zoom stays)
	var span := WAVE_CHUNK * stride
	draw_set_transform(Vector2(base_x + offset * ms_to_px, 0), 0, Vector2.ONE)
	var c := col(2)
	for ci in range(int(first / span), int(last / span) + 1):
		var pts = _wave_cache.get(ci)
		if pts == null:
			pts = _wave_piece(wave, ci * span, span, stride, step_ms * ms_to_px, H, classic)
			_wave_cache[ci] = pts
		if pts.size() >= 2:
			draw_polyline(pts, c, 1.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# one piece of the waveform: samples start .. start + span (plus the next
# piece's first one, so they join up), every stride-th
static func _wave_piece(wave, start: int, span: int, stride: int, px_per_sample: float, H: float, classic: bool) -> PoolVector2Array:
	var left: PoolRealArray = wave.left
	var right: PoolRealArray = wave.right
	var pts := PoolVector2Array()
	var end: int = min(wave.count - 1, start + span)
	var i := start
	while i <= end:
		var x := i * px_per_sample
		if classic:
			pts.append(Vector2(x, (2.0 - max(abs(left[i]), abs(right[i])) * 2.0) * H / 2))
		else:
			pts.append(Vector2(x, (left[i] + 1.0) * H / 2))
			pts.append(Vector2(x, (right[i] + 1.0) * H / 2))
		i += stride
	return pts
