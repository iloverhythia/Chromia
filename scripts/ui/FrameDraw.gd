extends Reference

# Frames (profile > Frames, FramesMenu.gd; the server's src/cards.js): a frame
# drawn around a round profile picture. Each card gives its frame:
#   Admin      royal: a ruby band between shimmering gold rims, a gold crown
#              with rubies on top, a ruby set in gold with laurels below
#   Developer  holographic: neon rings shifting cyan > blue > violet, HUD arcs
#              turning round, circuit traces with data running out, a </> chip
#   DJ         club: a ring of spectrum bars moving to a beat in pink, red and
#              orange, headphones with glowing cups, notes floating up
# and the looks an admin can give a card they make, in the card's colours:
# ring (polished metal), glow (neon tube), sparkle (twinkling stars), flame.
# Default is no frame. FrameView.gd draws one over a picture; the Spectate
# grid, Online players and profile use it. The website draws the same
# (website/assets/frames.js).
#
# Rings are meshes with a colour at every vertex (one draw call each): colours
# that change round the ring, light and dark edges like metal, soft glows,
# and a feathered edge instead of a jagged one. Everything is sized from the
# picture's radius r; a frame reaches about r * REACH from the middle.

const REACH := 1.45

const GOLD := [Color("#fff4c2"), Color("#f5c84c"), Color("#b8801e"), Color("#ffe08a"), Color("#d79b2b"), Color("#f9dc7a")]
const GOLD_TOP := Color("#fff1b0")
const GOLD_MID := Color("#f2b632")
const GOLD_LOW := Color("#9a6414")
const GOLD_EDGE := Color("#6b430a")

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
	return not fr.empty()

static func now() -> float:
	return OS.get_ticks_msec() / 1000.0

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
		"glow": _glow_style(ci, c, r, fr, t)
		"sparkle": _sparkle(ci, c, r, fr, t)
		"flame": _flame(ci, c, r, fr, t)
		_: _ring_style(ci, c, r, fr, t)

# ------------------------------------------------------------------ helpers

static func _pt(c: Vector2, rad: float, a: float) -> Vector2:
	return c + Vector2(cos(a), sin(a)) * rad

static func _shade(col: Color, k: float) -> Color:
	if k > 0.0:
		return col.lightened(k)
	if k < 0.0:
		return col.darkened(-k)
	return col

static func _with_a(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, a)

# a colour from evenly spaced stops round the ring (t: 0..1, loops)
static func _conic(stops: Array, t: float) -> Color:
	var n := stops.size()
	if n == 1:
		return stops[0]
	var x := fposmod(t, 1.0) * n
	var i := int(x) % n
	var a: Color = stops[i]
	var b: Color = stops[(i + 1) % n]
	return a.linear_interpolate(b, x - floor(x))

# A ring mesh: rings of vertices at `radii`, each with its alpha and its
# light/dark amount, coloured round the ring by `stops` (turned by `rot`).
static func _mesh_ring(ci: CanvasItem, c: Vector2, radii: Array, alphas: Array, shades: Array, stops: Array, rot: float, a0: float = 0.0, a1: float = TAU):
	var span: float = abs(a1 - a0)
	var seg := int(clamp(float(radii[radii.size() - 1]) * span * 0.35, 20.0, 180.0))
	var nr := radii.size()
	var pts := PoolVector2Array()
	var cols := PoolColorArray()
	var idx := PoolIntArray()
	for s in seg + 1:
		var a: float = a0 + (a1 - a0) * float(s) / float(seg)
		var base := _conic(stops, a / TAU + rot)
		var d := Vector2(cos(a), sin(a))
		for k in nr:
			pts.append(c + d * float(radii[k]))
			var col := _shade(base, float(shades[k]))
			col.a = base.a * float(alphas[k])
			cols.append(col)
	for s in seg:
		for k in nr - 1:
			var i0: int = s * nr + k
			idx.append(i0)
			idx.append(i0 + 1)
			idx.append(i0 + nr)
			idx.append(i0 + 1)
			idx.append(i0 + nr + 1)
			idx.append(i0 + nr)
	VisualServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)

# a solid band from r_in to r_out with a feathered edge; bevel: the light/dark
# amounts at its inner edge, middle and outer edge
static func _band(ci: CanvasItem, c: Vector2, r_in: float, r_out: float, stops: Array, rot: float = 0.0, bevel: Array = [0.0, 0.0, 0.0], alpha: float = 1.0, a0: float = 0.0, a1: float = TAU):
	var f: float = clamp((r_out - r_in) * 0.35, 0.6, 1.2)
	var m := (r_in + r_out) * 0.5
	_mesh_ring(ci, c, [r_in - f, r_in, m, r_out, r_out + f], [0.0, alpha, alpha, alpha, 0.0],
		[bevel[0], bevel[0], bevel[1], bevel[2], bevel[2]], stops, rot, a0, a1)

# a soft glow round radius r, w each way
static func _glow(ci: CanvasItem, c: Vector2, r: float, w: float, stops: Array, alpha: float, rot: float = 0.0):
	# (mostly outwards: inwards it would haze over the picture)
	_mesh_ring(ci, c, [r - w * 0.25, r - w * 0.08, r, r + w * 0.35, r + w], [0.0, alpha * 0.6, alpha, alpha * 0.55, 0.0],
		[0.0, 0.0, 0.1, 0.0, 0.0], stops, rot)

# a polygon shaded top to bottom (light to dark), with a crisp outline
static func _gpoly(ci: CanvasItem, pts: PoolVector2Array, top: Color, bottom: Color, outline: Color = Color(0, 0, 0, 0), ow: float = 1.0):
	var y0 := INF
	var y1 := -INF
	for p in pts:
		y0 = min(y0, p.y)
		y1 = max(y1, p.y)
	var cols := PoolColorArray()
	for p in pts:
		cols.append(top.linear_interpolate(bottom, (p.y - y0) / max(0.001, y1 - y0)))
	ci.draw_polygon(pts, cols)
	if outline.a > 0.0:
		var o := pts
		o.append(pts[0])
		ci.draw_polyline(o, outline, max(1.0, ow), true)

# a round light: a few circles fading out
static func _blob(ci: CanvasItem, p: Vector2, rad: float, col: Color, alpha: float = 1.0):
	for k in 4:
		var f: float = 1.0 - k * 0.22
		ci.draw_circle(p, rad * (1.0 + k * 0.6), _with_a(col, alpha * 0.28 * f * f))
	ci.draw_circle(p, rad * 0.55, _with_a(col.lightened(0.6), alpha))

static func _star4(ci: CanvasItem, p: Vector2, s: float, col: Color):
	if s <= 0.4:
		return
	var w := s * 0.2
	ci.draw_colored_polygon(PoolVector2Array([p + Vector2(0, -s), p + Vector2(w, -w), p + Vector2(s, 0), p + Vector2(w, w),
		p + Vector2(0, s), p + Vector2(-w, w), p + Vector2(-s, 0), p + Vector2(-w, -w)]), col)

static func _twinkle(ci: CanvasItem, p: Vector2, s: float, col: Color, k: float):
	if k <= 0.02:
		return
	ci.draw_circle(p, s * 0.55 * k, _with_a(col, 0.25 * k))
	_star4(ci, p, s * k, _with_a(col.lightened(0.5), 0.95 * k))
	_star4(ci, p, s * 0.45 * k, Color(1, 1, 1, k))

static func _pill(ci: CanvasItem, c: Vector2, w: float, h: float, col: Color):
	var rr := h / 2.0
	ci.draw_rect(Rect2(c.x - w / 2.0 + rr, c.y - rr, w - h, h), col)
	ci.draw_circle(Vector2(c.x - w / 2.0 + rr, c.y), rr, col)
	ci.draw_circle(Vector2(c.x + w / 2.0 - rr, c.y), rr, col)

static func _vpill_pts(c: Vector2, w: float, h: float) -> PoolVector2Array:
	var rr := w / 2.0
	var pts := PoolVector2Array()
	for i in 9:
		var a: float = PI + PI * i / 8.0
		pts.append(Vector2(c.x, c.y - h / 2.0 + rr) + Vector2(cos(a), sin(a)) * rr)
	for i in 9:
		var a: float = PI * i / 8.0
		pts.append(Vector2(c.x, c.y + h / 2.0 - rr) + Vector2(cos(a), sin(a)) * rr)
	return pts

static func _circle_pts(c: Vector2, rad: float, n: int) -> PoolVector2Array:
	var pts := PoolVector2Array()
	for i in n:
		pts.append(c + Vector2(cos(i * TAU / n), sin(i * TAU / n)) * rad)
	return pts

# ------------------------------------------------------------------ Admin

static func _admin(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var red: Color = fr.color
	var ruby := [red, red.darkened(0.45), red.lightened(0.18), red.darkened(0.3), red.lightened(0.05), red.darkened(0.5)]
	var pulse := 0.85 + 0.15 * sin(t * 1.6)
	# the glow behind
	_glow(ci, c, r * 1.1, r * 0.26, [red, Color("#f5c84c"), red], 0.42 * pulse, t * 0.03)
	# laurels below (behind the band)
	for sd in [-1.0, 1.0]:
		var side: float = sd
		for k in 5:
			var a: float = PI / 2.0 + side * (0.38 + k * 0.23)
			var p := _pt(c, r * 1.24 + k * r * 0.004, a)
			var tang := Vector2(-sin(a), cos(a)) * side
			var out := (p - c).normalized()
			var size: float = 1.0 - k * 0.1
			_leaf(ci, p, (tang * 0.75 + out * 0.65).normalized(), r * 0.2 * size, r * 0.085 * size)
			_leaf(ci, p, (tang * 0.85 - out * 0.45).normalized(), r * 0.17 * size, r * 0.07 * size)
		var s0: float = PI / 2.0 + side * 0.25
		var s1: float = PI / 2.0 + side * 1.42
		ci.draw_arc(c, r * 1.235, min(s0, s1), max(s0, s1), 18, GOLD_LOW, max(1.0, r * 0.03), true)
	# the ruby band, with light on its outer edge
	_band(ci, c, r * 1.02, r * 1.155, ruby, t * 0.02, [-0.35, 0.0, 0.22])
	# gold rims, their shine running round
	_band(ci, c, r * 0.985, r * 1.03, GOLD, t * 0.09, [-0.15, 0.3, -0.25])
	_band(ci, c, r * 1.145, r * 1.2, GOLD, -t * 0.07, [0.25, 0.1, -0.35])
	# studs: gold diamonds
	for i in 8:
		var a: float = i * TAU / 8.0 + TAU / 16.0
		var p := _pt(c, r * 1.088, a)
		var s := r * 0.05
		_gpoly(ci, PoolVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.75, 0), p + Vector2(0, s), p + Vector2(-s * 0.75, 0)]), GOLD_TOP, GOLD_LOW)
	# the ruby below, set in gold
	var g := _pt(c, r * 1.2, PI / 2.0)
	ci.draw_circle(g, r * 0.12, GOLD_EDGE)
	_gpoly(ci, _circle_pts(g, r * 0.108, 20), GOLD_TOP, GOLD_LOW)
	_gem(ci, g, r * 0.078, red)
	# the crown
	_crown(ci, Vector2(c.x, c.y - r * 1.1), r * 0.95, r * 0.56, red, t)
	# twinkles
	_twinkle(ci, _pt(c, r * 1.19, -PI * 0.78), r * 0.13, GOLD_TOP, max(0.0, sin(t * 1.9)))
	_twinkle(ci, _pt(c, r * 1.17, -PI * 0.15), r * 0.11, GOLD_TOP, max(0.0, sin(t * 1.9 + 2.2)))
	_twinkle(ci, _pt(c, r * 1.2, PI * 0.82), r * 0.1, GOLD_TOP, max(0.0, sin(t * 1.9 + 4.1)))

static func _leaf(ci: CanvasItem, p: Vector2, dir: Vector2, length: float, width: float):
	var side := Vector2(-dir.y, dir.x) * width * 0.5
	var tip := p + dir * length
	var pts := PoolVector2Array([p, p + dir * length * 0.3 + side, p + dir * length * 0.62 + side * 0.85, tip, p + dir * length * 0.62 - side * 0.85, p + dir * length * 0.3 - side])
	ci.draw_polygon(pts, PoolColorArray([GOLD_LOW, GOLD_MID, GOLD_TOP, GOLD_TOP, GOLD_MID, GOLD_LOW]))
	ci.draw_line(p, p + dir * length * 0.8, _with_a(GOLD_EDGE, 0.7), max(1.0, width * 0.12), true)

# a faceted gem: dark rim, light table, a white glint
static func _gem(ci: CanvasItem, p: Vector2, s: float, col: Color):
	var outer := PoolVector2Array()
	var inner := PoolVector2Array()
	for i in 8:
		var a: float = -PI / 2.0 + i * TAU / 8.0
		outer.append(p + Vector2(cos(a), sin(a)) * s)
		inner.append(p + Vector2(cos(a), sin(a)) * s * 0.55)
	_gpoly(ci, outer, col.lightened(0.15), col.darkened(0.55))
	_gpoly(ci, inner, col.lightened(0.55), col.darkened(0.1))
	ci.draw_circle(p + Vector2(-s * 0.28, -s * 0.32), s * 0.18, Color(1, 1, 1, 0.85))

static func _crown(ci: CanvasItem, base: Vector2, cw: float, ch: float, red: Color, t: float):
	var P := []
	for uv in [Vector2(-0.5, 0), Vector2(-0.56, -0.72), Vector2(-0.27, -0.42), Vector2(0, -1), Vector2(0.27, -0.42), Vector2(0.56, -0.72), Vector2(0.5, 0)]:
		var u: Vector2 = uv
		P.append(base + Vector2(u.x * cw, u.y * ch))
	var body := PoolVector2Array(P)
	# shadow, body, then the band across the bottom
	var sh := PoolVector2Array()
	for p in body:
		sh.append(p + Vector2(0, ch * 0.06))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	_gpoly(ci, body, GOLD_TOP, GOLD_LOW, GOLD_EDGE, cw * 0.025)
	# a lighter middle face (gives it some depth)
	_gpoly(ci, PoolVector2Array([base + Vector2(-0.16 * cw, 0), base + Vector2(0, -0.86 * ch), base + Vector2(0.16 * cw, 0)]), Color(1, 0.97, 0.8, 0.55), Color(1, 0.9, 0.5, 0.0))
	var band := PoolVector2Array([base + Vector2(-0.53 * cw, -0.24 * ch), base + Vector2(0.53 * cw, -0.24 * ch), base + Vector2(0.5 * cw, 0.04 * ch), base + Vector2(-0.5 * cw, 0.04 * ch)])
	_gpoly(ci, band, GOLD_MID, GOLD_LOW, GOLD_EDGE, cw * 0.022)
	for k in 3:
		var tip: Vector2 = P[[1, 3, 5][k]]
		ci.draw_circle(tip, cw * 0.065, GOLD_EDGE)
		ci.draw_circle(tip, cw * 0.052, GOLD_TOP)
		_gem(ci, tip, cw * 0.04, red)
	_gem(ci, base + Vector2(0, -0.1 * ch), cw * 0.07, Color("#3aa7ff"))
	_gem(ci, base + Vector2(-0.3 * cw, -0.1 * ch), cw * 0.045, red)
	_gem(ci, base + Vector2(0.3 * cw, -0.1 * ch), cw * 0.045, red)
	# a glint sliding across now and then
	var gl: float = fmod(t * 0.45, 2.2) - 0.6
	if gl >= -0.5 and gl <= 0.5:
		_twinkle(ci, base + Vector2(gl * cw * 0.9, -0.5 * ch), cw * 0.16, GOLD_TOP, 1.0 - abs(gl) * 2.0)

# ------------------------------------------------------------------ Developer

const DEV_TRACES := [[-150, 1], [-124, -1], [-56, 1], [-32, -1], [10, 1], [36, -1], [144, 1], [170, -1]]

static func _developer(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var main: Color = fr.color
	var holo := [Color("#22d3ee"), main, Color("#8b5cf6"), Color("#38bdf8"), main.lightened(0.2), Color("#a78bfa")]
	var glass: Color = fr.color2.darkened(0.35)
	_glow(ci, c, r * 1.1, r * 0.3, holo, 0.38, t * 0.05)
	# circuit traces (behind the rings)
	for i in DEV_TRACES.size():
		var a: float = deg2rad(float(DEV_TRACES[i][0]))
		var bend: float = float(DEV_TRACES[i][1])
		var col := _conic(holo, a / TAU + t * 0.05)
		var p0 := _pt(c, r * 1.17, a)
		var p1 := _pt(c, r * 1.29, a)
		var p2 := p1 + Vector2(cos(a), sin(a)).rotated(bend * PI / 4.0) * r * 0.14
		var line := PoolVector2Array([p0, p1, p2])
		ci.draw_polyline(line, _with_a(col, 0.25), max(1.0, r * 0.07), true)
		ci.draw_polyline(line, _with_a(col.lightened(0.25), 0.95), max(1.0, r * 0.024), true)
		ci.draw_circle(p2, r * 0.05, _with_a(col, 0.3))
		ci.draw_circle(p2, r * 0.036, col)
		ci.draw_circle(p2, r * 0.018, glass)
		# data running out, with a short trail
		var l1 := p0.distance_to(p1)
		var l2 := p1.distance_to(p2)
		for k in 3:
			var f := fmod(t * 0.65 + i * 0.37 - k * 0.04 + 1.0, 1.0)
			var d := f * (l1 + l2)
			var pp := p0.linear_interpolate(p1, d / l1) if d < l1 else p1.linear_interpolate(p2, (d - l1) / l2)
			ci.draw_circle(pp, r * (0.03 - k * 0.007), Color(0.85, 0.97, 1, (1.0 - f * 0.7) * (1.0 - k * 0.35)))
	# the glass band and its neon edges
	_band(ci, c, r * 1.0, r * 1.17, [glass], 0.0, [0.1, -0.1, 0.15], 0.85)
	_band(ci, c, r * 0.985, r * 1.025, holo, t * 0.06, [0.15, 0.45, 0.1])
	_band(ci, c, r * 1.15, r * 1.18, holo, -t * 0.05, [0.1, 0.4, 0.05])
	# ticks round the band
	for i in 48:
		var a: float = i * TAU / 48.0
		var long: bool = i % 4 == 0
		ci.draw_line(_pt(c, r * (1.04 if long else 1.055), a), _pt(c, r * 1.075, a), _with_a(_conic(holo, a / TAU + t * 0.06), 0.55 if long else 0.3), max(1.0, r * 0.012), true)
	# HUD arcs turning, one way and the other
	for k in 3:
		var a0: float = t * 0.55 + k * TAU / 3.0
		_band(ci, c, r * 1.095, r * 1.125, holo, t * 0.06, [0.2, 0.5, 0.2], 0.95, a0, a0 + 0.9)
	for k in 4:
		var a0b: float = -t * 0.35 + k * TAU / 4.0
		_band(ci, c, r * 1.13, r * 1.14, holo, 0.3, [0.4, 0.6, 0.4], 0.7, a0b, a0b + 0.35)
	# the </> chip
	var tc := _pt(c, r * 1.17, PI / 2.0)
	var h := r * 0.32
	var w := r * 0.78
	_pill(ci, tc, w + r * 0.14, h + r * 0.14, _with_a(main, 0.22))
	_pill(ci, tc, w + r * 0.05, h + r * 0.05, Color("#22d3ee").linear_interpolate(Color("#8b5cf6"), 0.5 + 0.5 * sin(t)))
	_pill(ci, tc, w, h, glass)
	var sym := Color(0.8, 0.96, 1)
	var q := h * 0.27
	var sw: float = max(1.0, r * 0.04)
	ci.draw_polyline(PoolVector2Array([tc + Vector2(-w * 0.15, -q), tc + Vector2(-w * 0.29, 0), tc + Vector2(-w * 0.15, q)]), sym, sw, true)
	ci.draw_polyline(PoolVector2Array([tc + Vector2(w * 0.15, -q), tc + Vector2(w * 0.29, 0), tc + Vector2(w * 0.15, q)]), sym, sw, true)
	ci.draw_line(tc + Vector2(w * 0.06, -q * 1.15), tc + Vector2(-w * 0.06, q * 1.15), Color("#67e8f9"), sw, true)

# ------------------------------------------------------------------ DJ

static func _dj(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var main: Color = fr.color
	var club := [Color("#ff2d75"), main, Color("#ff8a00"), Color("#ff2dd4"), Color("#ff4d4d")]
	var beat: float = pow(max(0.0, sin(t * PI * 2.0 * 1.05)), 8.0) # (about 126 BPM)
	_glow(ci, c, r * 1.12, r * 0.32, club, 0.3 + beat * 0.35, t * 0.08)
	# the spectrum: bars all round but the top (where the headband is)
	var n := 34
	var from := -PI / 2.0 + 0.95
	var span := TAU - 1.9
	for i in n:
		var u := float(i) / float(n - 1)
		var a: float = from + span * u
		var mid: float = 1.0 - abs(u - 0.5) * 2.0
		var e: float = abs(sin(t * 3.1 + i * 0.73) * sin(t * 1.7 + i * 0.29 + 1.0))
		e = clamp(e * (0.55 + 0.45 * mid) + beat * 0.45 * mid, 0.0, 1.0)
		var h := r * (0.05 + 0.25 * e)
		var col := _conic(club, a / TAU + t * 0.06)
		var d := Vector2(cos(a), sin(a))
		var sd := Vector2(-d.y, d.x) * r * 0.032
		var b := c + d * r * 1.13
		var tip := b + d * h
		ci.draw_polygon(PoolVector2Array([b - sd, b + sd, tip + sd, tip - sd]),
			PoolColorArray([col.darkened(0.25), col.darkened(0.25), _with_a(col.lightened(0.45), 0.95), _with_a(col.lightened(0.45), 0.95)]))
		ci.draw_circle(tip, r * 0.032, _with_a(col.lightened(0.6), 0.9))
	# the ring
	_band(ci, c, r * 0.99, r * 1.1, [Color("#1a0810")], 0.0, [0.15, -0.1, 0.1])
	_band(ci, c, r * 0.985, r * 1.025, club, t * 0.12, [0.1, 0.45, 0.1])
	_band(ci, c, r * 1.075, r * 1.1, club, -t * 0.1, [0.05, 0.35, 0.0], 0.9)
	# headphones: the band over the top
	var metal := [Color("#2b2b33"), Color("#5c5c6a"), Color("#2b2b33"), Color("#45454f")]
	_band(ci, c, r * 1.17, r * 1.33, metal, 0.0, [-0.3, 0.25, -0.45], 1.0, PI + 0.3, TAU - 0.3)
	_band(ci, c, r * 1.235, r * 1.265, club, t * 0.2, [0.2, 0.55, 0.2], 0.95, PI + 0.55, TAU - 0.55)
	# the cups, thumping on the beat
	var cs: float = 1.0 + beat * 0.06
	for sdv in [-1.0, 1.0]:
		var side: float = sdv
		var cc := c + Vector2(side * r * 1.16, -r * 0.06)
		var cw := r * 0.3 * cs
		var chh := r * 0.62 * cs
		var arm := _pt(c, r * 1.25, PI + 0.33 if side < 0 else TAU - 0.33)
		ci.draw_line(arm, cc + Vector2(0, -chh * 0.42), Color("#3a3a44"), r * 0.1, true)
		ci.draw_colored_polygon(_vpill_pts(cc + Vector2(0, chh * 0.05), cw, chh), Color(0, 0, 0, 0.4))
		_gpoly(ci, _vpill_pts(cc, cw, chh), Color("#5a5a66"), Color("#1d1d24"), Color("#0e0e12"), r * 0.02)
		var led := _conic(club, (0.25 if side > 0 else 0.75) + t * 0.1)
		_gpoly(ci, _vpill_pts(cc + Vector2(side * cw * 0.1, 0), cw * 0.62, chh * 0.78), led.lightened(0.15), led.darkened(0.35))
		_gpoly(ci, _vpill_pts(cc + Vector2(side * cw * 0.1, 0), cw * 0.38, chh * 0.55), Color("#24242c"), Color("#111116"))
		_blob(ci, cc + Vector2(side * cw * 0.1, -chh * 0.12), r * 0.03, led, 0.6 + beat * 0.4)
	# notes floating up
	for k in 2:
		var ph := fmod(t * 0.35 + k * 0.5, 1.0)
		var side2: float = -1.0 if k == 0 else 1.0
		var np := c + Vector2(side2 * r * (1.3 + 0.05 * sin(t * 2.0 + k)), r * 0.35 - ph * r * 0.95)
		_note(ci, np, r * 0.1, _with_a(_conic(club, k * 0.4 + t * 0.1).lightened(0.3), sin(ph * PI)))

static func _note(ci: CanvasItem, p: Vector2, s: float, col: Color):
	if col.a <= 0.02:
		return
	ci.draw_circle(p, s * 0.42, col)
	ci.draw_line(p + Vector2(s * 0.36, 0), p + Vector2(s * 0.36, -s * 1.3), col, max(1.0, s * 0.16), true)
	ci.draw_line(p + Vector2(s * 0.36, -s * 1.3), p + Vector2(s * 0.95, -s * 0.95), col, max(1.0, s * 0.16), true)

# ------------------------------------------------------------------ the looks for cards admins make

static func _ring_style(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var metal := [col, col.lightened(0.45), col, col.darkened(0.35), col.lightened(0.2), col.darkened(0.2)]
	_glow(ci, c, r * 1.08, r * 0.18, [col], 0.25)
	_band(ci, c, r * 0.99, r * 1.13, metal, t * 0.05, [-0.3, 0.15, 0.3])
	_band(ci, c, r * 1.135, r * 1.165, [col.lightened(0.3), col, col.lightened(0.5)], -t * 0.05, [0.2, 0.4, -0.1])
	_band(ci, c, r * 0.975, r * 1.0, [fr.color2.lightened(0.4)], 0.0, [0.0, 0.3, 0.0], 0.8)

static func _glow_style(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var p := 0.75 + 0.25 * sin(t * 2.2)
	var hue := [col, col.lightened(0.25), col, _shade(fr.color2, 0.4).linear_interpolate(col, 0.5)]
	_glow(ci, c, r * 1.07, r * 0.42, hue, 0.55 * p, t * 0.1)
	_glow(ci, c, r * 1.07, r * 0.16, hue, 0.8 * p, -t * 0.1)
	_band(ci, c, r * 1.03, r * 1.11, hue, t * 0.1, [0.1, 0.75, 0.1])
	var s := fmod(t * 0.8, TAU)
	_band(ci, c, r * 1.05, r * 1.09, [Color(1, 1, 1)], 0.0, [0.0, 0.0, 0.0], 0.75, s, s + 0.6)

const SPARKS := [[-100, 0.0, 1.0], [-35, 1.7, 0.8], [25, 3.1, 0.9], [95, 0.9, 1.1], [150, 2.4, 0.8], [-160, 4.0, 1.0], [200, 5.2, 0.7], [60, 2.9, 0.6]]

static func _sparkle(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var hue := [col, col.lightened(0.5), col, fr.color2.lightened(0.5)]
	_glow(ci, c, r * 1.08, r * 0.22, hue, 0.35, t * 0.04)
	_band(ci, c, r * 0.99, r * 1.1, hue, t * 0.08, [-0.2, 0.3, 0.1])
	_band(ci, c, r * 1.12, r * 1.14, [col.lightened(0.4)], 0.0, [0.0, 0.2, 0.0], 0.7)
	# little lights going round
	for i in 10:
		var a: float = i * TAU / 10.0 + t * 0.4
		ci.draw_circle(_pt(c, r * 1.13, a), r * 0.016, Color(1, 1, 1, 0.8))
	for s in SPARKS:
		var a: float = deg2rad(float(s[0]))
		var k: float = max(0.0, sin(t * 2.2 + float(s[1])))
		_twinkle(ci, _pt(c, r * (1.22 + 0.06 * sin(float(s[1]) * 3.0)), a), r * 0.17 * float(s[2]), col, k)

static func _flame(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var hot := col.linear_interpolate(Color("#ffe27a"), 0.75)
	_glow(ci, c, r * 1.12, r * 0.3, [col, hot, col], 0.45 + 0.1 * sin(t * 9.0), t * 0.2)
	var n := 22
	var heights := [0.3, 0.22, 0.13]
	var widths := [0.2, 0.15, 0.09]
	for layer in 3:
		var cb: Color = [col.darkened(0.2), col.lightened(0.1), hot][layer]
		var ct: Color = [_with_a(col, 0.0), _with_a(hot, 0.0), Color(1, 1, 0.85, 0.0)][layer]
		for i in n:
			var a: float = i * TAU / n + layer * 0.37
			var out := Vector2(cos(a), sin(a))
			# (fire goes up: each flame leans that way, the top ones are tallest)
			var dir := (out + Vector2(0, -0.75)).normalized()
			var up: float = 0.55 + 0.45 * max(0.0, -out.y)
			var flick := sin(t * 7.0 + i * 1.9 + layer * 2.0) * 0.05 + sin(t * 12.7 + i * 0.7 + layer) * 0.03
			var h := r * (float(heights[layer]) * up + flick)
			var w := r * float(widths[layer])
			var side := Vector2(-dir.y, dir.x)
			var b := c + out * r * 1.04
			var sway := side * sin(t * 4.0 + i + layer) * r * 0.04
			var tip := b + dir * h + sway
			var mid := b + dir * h * 0.45 + sway * 0.4
			ci.draw_polygon(PoolVector2Array([b - side * w * 0.5, mid - side * w * 0.4, tip, mid + side * w * 0.4, b + side * w * 0.5]),
				PoolColorArray([cb, cb.linear_interpolate(ct, 0.3), ct, cb.linear_interpolate(ct, 0.3), cb]))
	_band(ci, c, r * 0.99, r * 1.08, [col.darkened(0.45), col.darkened(0.2), col.darkened(0.5)], t * 0.1, [-0.2, 0.1, 0.2])
	_band(ci, c, r * 1.0, r * 1.03, [hot, col.lightened(0.3), hot], t * 0.3, [0.1, 0.5, 0.1])
	# embers drifting up
	for k in 6:
		var ph := fmod(t * 0.4 + k * 0.17, 1.0)
		var x: float = sin(k * 2.3) * r * 1.1 + sin(t * 2.0 + k) * r * 0.05
		var y: float = -r * 0.6 - ph * r * 0.9
		ci.draw_circle(c + Vector2(x, y), r * 0.022 * (1.0 - ph), _with_a(hot.lightened(0.3), (1.0 - ph) * 0.9))
