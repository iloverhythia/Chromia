extends Reference

# Frames (profile > Frames, FramesMenu.gd; the server's src/cards.js): a frame
# drawn around a round profile picture. Each card gives its frame, so the
# looks follow the cards: Admin a gold crown and laurels on a crimson band,
# Developer circuit lines with data running along them and a </> tag, DJ
# headphones with sound bars moving to a beat. Cards an admin makes pick one
# of the plain looks (ring, glow, sparkle, flame) in the card's colours.
# Default is no frame. FrameView.gd draws one over a picture; the Spectate
# grid and Online players draw them straight onto their cards.
#
# Everything is drawn with lines and polygons (no pictures), sized from the
# picture's radius r. A frame reaches about r * REACH out from the middle.

const REACH := 1.42
const GOLD := Color("#ffcf4a")
const GOLD_DARK := Color("#9c6b12")

# the server's frame ({id, name, style, color, color2}) -> what draw() takes;
# {} for no frame
static func parse(f) -> Dictionary:
	if not (f is Dictionary):
		return {}
	var st := String(f.get("style", ""))
	if st == "" or st == "none":
		return {}
	var c1 := String(f.get("color", ""))
	var c2 := String(f.get("color2", ""))
	return {
		"id": String(f.get("id", "")), "name": String(f.get("name", "")), "style": st,
		"color": Color(c1) if c1.is_valid_html_color() else Color("#a78bfa"),
		"color2": Color(c2) if c2.is_valid_html_color() else Color("#13111a"),
	}

static func animated(fr: Dictionary) -> bool:
	return not fr.empty() and String(fr.style) != "ring"

static func now() -> float:
	return OS.get_ticks_msec() / 1000.0

static func _pt(c: Vector2, rad: float, a: float) -> Vector2:
	return c + Vector2(cos(a), sin(a)) * rad

# (ci: the Control drawing it, in its _draw or "draw" signal; c: the
# picture's middle; t: seconds, for the moving parts)
static func draw(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float = -1.0):
	if fr.empty() or r <= 1.0:
		return
	if t < 0.0:
		t = now()
	match String(fr.style):
		"admin": _admin(ci, c, r, fr, t)
		"developer": _developer(ci, c, r, fr, t)
		"dj": _dj(ci, c, r, fr, t)
		"glow": _glow(ci, c, r, fr, t)
		"sparkle": _sparkle(ci, c, r, fr, t)
		"flame": _flame(ci, c, r, fr, t)
		_: _ring(ci, c, r, fr)

static func _ring_line(ci: CanvasItem, c: Vector2, rad: float, col: Color, w: float):
	ci.draw_arc(c, rad, 0.0, TAU, int(clamp(rad * 0.9, 32, 96)), col, max(1.0, w), true)

# ---- Admin: a crimson band edged in gold, gold studs, a crown on top and
# laurel branches round the bottom with a gem; a shine runs round the gold

static func _admin(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var red: Color = fr.color
	var deep: Color = red.darkened(0.6)
	var lw: float = max(1.0, r * 0.028)
	# the laurels first (under the band)
	for sd in [-1.0, 1.0]:
		var side: float = sd
		for k in 6:
			var a: float = PI / 2.0 + side * (0.42 + k * 0.2)
			var p := _pt(c, r * 1.25, a)
			var tang := Vector2(-sin(a), cos(a)) * side # (along the branch, up the side)
			var out := (p - c).normalized()
			var dir := (tang * 0.8 + out * 0.6).normalized()
			_leaf(ci, p, dir, r * 0.17, r * 0.075, Color("#e8b33a") if k % 2 == 0 else Color("#c8922a"))
			_leaf(ci, p - out * r * 0.02, (tang * 0.8 - out * 0.5).normalized(), r * 0.14, r * 0.06, Color("#b07e22"))
		ci.draw_arc(c, r * 1.22, PI / 2.0 + side * 0.3, PI / 2.0 + side * 1.55, 16, GOLD_DARK, lw, true)
	# the band
	_ring_line(ci, c, r * 1.08, deep, r * 0.15)
	_ring_line(ci, c, r * 1.08, red, r * 0.075)
	_ring_line(ci, c, r * 1.005, GOLD, lw)
	_ring_line(ci, c, r * 1.155, GOLD, lw)
	# studs round it
	for i in 12:
		var a: float = i * TAU / 12.0 + TAU / 24.0
		_diamond(ci, _pt(c, r * 1.08, a), r * 0.045, GOLD)
	# the shine
	var s := fmod(t * 0.9, TAU)
	ci.draw_arc(c, r * 1.155, s, s + 0.5, 10, Color(1, 1, 0.85, 0.85), lw * 1.6, true)
	ci.draw_arc(c, r * 1.005, s + PI, s + PI + 0.5, 10, Color(1, 1, 0.85, 0.6), lw * 1.4, true)
	# the gem at the bottom
	var g := _pt(c, r * 1.2, PI / 2.0)
	ci.draw_circle(g, r * 0.085, GOLD)
	ci.draw_circle(g, r * 0.06, red.lightened(0.1))
	ci.draw_circle(g + Vector2(-0.02, -0.025) * r, r * 0.02, Color(1, 1, 1, 0.8))
	# the crown
	var cw := r * 0.86
	var ch := r * 0.5
	var base := Vector2(c.x, c.y - r * 1.06)
	var pts := PoolVector2Array()
	for uv0 in [Vector2(-0.5, 0), Vector2(-0.5, -0.72), Vector2(-0.25, -0.38), Vector2(0, -1), Vector2(0.25, -0.38), Vector2(0.5, -0.72), Vector2(0.5, 0)]:
		var uv: Vector2 = uv0
		pts.append(base + Vector2(uv.x * cw, uv.y * ch))
	ci.draw_colored_polygon(pts, GOLD)
	var outline := pts
	outline.append(pts[0])
	ci.draw_polyline(outline, GOLD_DARK, lw, true)
	ci.draw_rect(Rect2(base + Vector2(-0.5 * cw, -0.2 * ch), Vector2(cw, 0.2 * ch)), Color("#e0a72e"))
	ci.draw_line(base + Vector2(-0.5 * cw, -0.2 * ch), base + Vector2(0.5 * cw, -0.2 * ch), GOLD_DARK, lw, true)
	for tip in [Vector2(-0.5, -0.72), Vector2(0, -1), Vector2(0.5, -0.72)]:
		var tp: Vector2 = base + Vector2(tip.x * cw, tip.y * ch)
		ci.draw_circle(tp, r * 0.055, GOLD_DARK)
		ci.draw_circle(tp, r * 0.04, red.lightened(0.15))
	for gx0 in [-0.27, 0.0, 0.27]:
		var gx: float = gx0
		ci.draw_circle(base + Vector2(gx * cw, -0.1 * ch), r * 0.03, red if gx != 0.0 else Color("#4ac6ff"))
	# (a glint across the crown)
	var gl: float = fmod(t * 0.5, 2.0) - 0.5
	if gl >= -0.5 and gl <= 0.5:
		var gp := base + Vector2(gl * cw, -0.45 * ch)
		_star4(ci, gp, r * 0.12, Color(1, 1, 0.9, 0.9 * (1.0 - abs(gl) * 2.0)))

static func _leaf(ci: CanvasItem, p: Vector2, dir: Vector2, length: float, width: float, col: Color):
	var side := Vector2(-dir.y, dir.x) * width * 0.5
	var tip := p + dir * length
	var mid := p + dir * length * 0.45
	ci.draw_colored_polygon(PoolVector2Array([p, mid + side, tip, mid - side]), col)

static func _diamond(ci: CanvasItem, p: Vector2, s: float, col: Color):
	ci.draw_colored_polygon(PoolVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.7, 0), p + Vector2(0, s), p + Vector2(-s * 0.7, 0)]), col)

static func _star4(ci: CanvasItem, p: Vector2, s: float, col: Color):
	if s <= 0.3:
		return
	var w := s * 0.22
	ci.draw_colored_polygon(PoolVector2Array([p + Vector2(0, -s), p + Vector2(w, -w), p + Vector2(s, 0), p + Vector2(w, w),
		p + Vector2(0, s), p + Vector2(-w, w), p + Vector2(-s, 0), p + Vector2(-w, -w)]), col)

# ---- Developer: a blue double ring with data dashes running between, circuit
# traces out to little pads with pulses running along them, a </> tag below

const DEV_TRACES := [[-150, 1], [-122, -1], [-58, 1], [-30, -1], [12, 1], [38, -1], [142, 1], [168, -1]]

static func _developer(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var blue: Color = fr.color
	var dark: Color = fr.color2.darkened(0.2)
	var lw: float = max(1.0, r * 0.03)
	# traces
	for i in DEV_TRACES.size():
		var a: float = deg2rad(float(DEV_TRACES[i][0]))
		var bend: float = float(DEV_TRACES[i][1])
		var p0 := _pt(c, r * 1.13, a)
		var p1 := _pt(c, r * 1.27, a)
		var out := Vector2(cos(a), sin(a))
		var p2 := p1 + out.rotated(bend * PI / 4.0) * r * 0.13
		ci.draw_polyline(PoolVector2Array([p0, p1, p2]), Color(blue.r, blue.g, blue.b, 0.85), lw, true)
		ci.draw_circle(p2, r * 0.045, blue)
		ci.draw_circle(p2, r * 0.022, dark)
		# a pulse running out along it
		var f := fmod(t * 0.7 + i * 0.37, 1.0)
		var l1 := p0.distance_to(p1)
		var l2 := p1.distance_to(p2)
		var d := f * (l1 + l2)
		var pp := p0.linear_interpolate(p1, d / l1) if d < l1 else p1.linear_interpolate(p2, (d - l1) / l2)
		ci.draw_circle(pp, r * 0.03, Color(0.85, 0.95, 1, 1.0 - f * 0.6))
	# rings
	_ring_line(ci, c, r * 1.08, dark, r * 0.12)
	_ring_line(ci, c, r * 1.03, blue, lw * 1.4)
	_ring_line(ci, c, r * 1.13, Color(blue.r, blue.g, blue.b, 0.75), lw)
	# data running round between them
	for i in 20:
		var a: float = i * TAU / 20.0 + t * 0.5
		ci.draw_arc(c, r * 1.08, a, a + 0.12, 3, blue.lightened(0.45), max(1.0, r * 0.03), true)
	# the </> tag
	var tc := _pt(c, r * 1.13, PI / 2.0)
	var h := r * 0.3
	var w := r * 0.7
	_pill(ci, tc, w + lw * 2.0, h + lw * 2.0, blue)
	_pill(ci, tc, w, h, dark)
	var sym: Color = blue.lightened(0.35)
	var q := h * 0.28
	var sw: float = max(1.0, r * 0.035)
	ci.draw_polyline(PoolVector2Array([tc + Vector2(-w * 0.16, -q), tc + Vector2(-w * 0.3, 0), tc + Vector2(-w * 0.16, q)]), sym, sw, true)
	ci.draw_polyline(PoolVector2Array([tc + Vector2(w * 0.16, -q), tc + Vector2(w * 0.3, 0), tc + Vector2(w * 0.16, q)]), sym, sw, true)
	ci.draw_line(tc + Vector2(w * 0.06, -q * 1.15), tc + Vector2(-w * 0.06, q * 1.15), sym, sw, true)
	# (a cursor that blinks after it)
	if fmod(t, 1.0) < 0.5:
		ci.draw_rect(Rect2(tc + Vector2(w * 0.36, -q), Vector2(sw, q * 2.0)), sym)

static func _pill(ci: CanvasItem, c: Vector2, w: float, h: float, col: Color):
	var rr := h / 2.0
	ci.draw_rect(Rect2(c.x - w / 2.0 + rr, c.y - rr, w - h, h), col)
	ci.draw_circle(Vector2(c.x - w / 2.0 + rr, c.y), rr, col)
	ci.draw_circle(Vector2(c.x + w / 2.0 - rr, c.y), rr, col)

# ---- DJ: headphones over the top, a red ring, and sound bars round the
# bottom jumping to a beat (the ear cups thump on it too)

static func _dj(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var red: Color = fr.color
	var pink := red.linear_interpolate(Color("#ff8fc0"), 0.6)
	var beat: float = pow(max(0.0, sin(t * PI * 2.0 * 1.05)), 10.0) # (about 126 BPM)
	# the bars
	var n := 19
	for i in n:
		var a: float = lerp(0.52, PI - 0.52, float(i) / float(n - 1))
		var e: float = abs(sin(t * 3.3 + i * 0.85) * sin(t * 1.9 + i * 0.37 + 1.0))
		e = clamp(e * 0.8 + beat * 0.35 * (1.0 - abs(float(i) / float(n - 1) - 0.5)), 0.0, 1.0)
		var h := r * (0.06 + 0.22 * e)
		ci.draw_line(_pt(c, r * 1.12, a), _pt(c, r * 1.12 + h, a), red.linear_interpolate(pink, e), max(1.0, r * 0.065), true)
	# the ring
	_ring_line(ci, c, r * 1.045, red.darkened(0.55), r * 0.1)
	_ring_line(ci, c, r * 1.045, red, max(1.0, r * 0.045))
	# the band over the top
	var band := Color(0.24, 0.23, 0.27)
	ci.draw_arc(c, r * 1.24, PI + 0.32, TAU - 0.32, 40, Color(0.06, 0.06, 0.07), r * 0.16, true)
	ci.draw_arc(c, r * 1.24, PI + 0.32, TAU - 0.32, 40, band, r * 0.12, true)
	ci.draw_arc(c, r * 1.24, PI + 0.5, TAU - 0.5, 40, red, max(1.0, r * 0.04), true)
	ci.draw_arc(c, r * 1.3, PI + 0.9, TAU - 0.9, 30, Color(1, 1, 1, 0.18), max(1.0, r * 0.025), true)
	# the ear cups
	var cs: float = 1.0 + beat * 0.07
	for sd in [-1.0, 1.0]:
		var side: float = sd
		var cc := c + Vector2(side * r * 1.14, -r * 0.08)
		var cw := r * 0.26 * cs
		var chh := r * 0.56 * cs
		var arm_from := _pt(c, r * 1.24, PI + 0.34 if side < 0 else TAU - 0.34)
		ci.draw_line(arm_from, cc + Vector2(0, -chh * 0.4), band, r * 0.09, true)
		_vpill(ci, cc, cw, chh, band)
		_vpill(ci, cc + Vector2(side * cw * 0.12, 0), cw * 0.62, chh * 0.78, red.darkened(0.15))
		_vpill(ci, cc + Vector2(side * cw * 0.12, -chh * 0.1), cw * 0.24, chh * 0.4, Color(1, 1, 1, 0.22 + beat * 0.3))

static func _vpill(ci: CanvasItem, c: Vector2, w: float, h: float, col: Color):
	var rr := w / 2.0
	ci.draw_rect(Rect2(c.x - rr, c.y - h / 2.0 + rr, w, h - w), col)
	ci.draw_circle(Vector2(c.x, c.y - h / 2.0 + rr), rr, col)
	ci.draw_circle(Vector2(c.x, c.y + h / 2.0 - rr), rr, col)

# ---- the plain looks for cards admins make

static func _ring(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary):
	var col: Color = fr.color
	_ring_line(ci, c, r * 1.05, col, r * 0.07)
	_ring_line(ci, c, r * 1.13, Color(col.r, col.g, col.b, 0.6), max(1.0, r * 0.025))
	_ring_line(ci, c, r * 1.005, fr.color2.lightened(0.35), max(1.0, r * 0.02))

static func _glow(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var p := 0.7 + 0.3 * sin(t * 2.2)
	for k in 5:
		_ring_line(ci, c, r * (1.06 + k * 0.045), Color(col.r, col.g, col.b, (0.42 - k * 0.08) * p), r * 0.06)
	_ring_line(ci, c, r * 1.04, col.lightened(0.2), r * 0.06)
	_ring_line(ci, c, r * 1.04, Color(1, 1, 1, 0.35 * p), max(1.0, r * 0.02))

const SPARKS := [[-100, 0.0], [-35, 1.7], [25, 3.1], [95, 0.9], [150, 2.4], [-160, 4.0], [200, 5.2]]

static func _sparkle(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	_ring_line(ci, c, r * 1.05, col, r * 0.06)
	_ring_line(ci, c, r * 1.11, Color(col.r, col.g, col.b, 0.5), max(1.0, r * 0.02))
	for s in SPARKS:
		var a: float = deg2rad(float(s[0]))
		var k: float = max(0.0, sin(t * 2.4 + float(s[1])))
		var p := _pt(c, r * (1.2 + 0.06 * sin(float(s[1]) * 3.0)), a)
		_star4(ci, p, r * 0.16 * k, Color(1, 1, 1, 0.9 * k))
		_star4(ci, p, r * 0.1 * k, col.lightened(0.5))
	var s2 := fmod(t * 0.7, TAU)
	ci.draw_arc(c, r * 1.05, s2, s2 + 0.35, 8, Color(1, 1, 1, 0.7), max(1.0, r * 0.03), true)

static func _flame(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var hot := col.linear_interpolate(Color("#ffe27a"), 0.7)
	var n := 20
	for layer in 2:
		for i in n:
			var a: float = i * TAU / n + (0.5 * TAU / n if layer == 1 else 0.0)
			var flick := sin(t * 7.0 + i * 1.9 + layer) * 0.06 + sin(t * 12.7 + i * 0.7) * 0.03
			var h := r * ((0.2 if layer == 0 else 0.13) + flick)
			var w := r * (0.2 if layer == 0 else 0.15)
			var out := Vector2(cos(a), sin(a))
			var side := Vector2(-out.y, out.x)
			var b := c + out * r * 1.02
			var sway := side * sin(t * 4.0 + i) * r * 0.03
			var tip := b + out * h + sway
			var shade: Color = col if layer == 0 else hot
			ci.draw_colored_polygon(PoolVector2Array([b - side * w * 0.5, b + out * h * 0.45 - side * w * 0.38, tip, b + out * h * 0.45 + side * w * 0.38, b + side * w * 0.5]), shade)
	_ring_line(ci, c, r * 1.03, col.darkened(0.4), r * 0.07)
	_ring_line(ci, c, r * 1.03, hot, max(1.0, r * 0.025))
