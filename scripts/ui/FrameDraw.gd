extends Reference

# Frames (profile > Frames, FramesMenu.gd; the server's src/cards.js): a frame
# drawn around a round profile picture. Each card gives its frame:
#   Admin      royal: a ruby band between shimmering gold rims, a gold crown
#              with rubies on top, a ruby set in gold with laurels below
#   Developer  holographic: neon rings shifting cyan > blue > violet, HUD arcs
#              turning round, circuit traces with data running out, a </> chip
#   DJ         club: a ring of spectrum bars moving to a beat in pink, red and
#              orange, headphones with glowing cups, notes floating up
#   Ranker, Contributor, Tester, Moderator   a ring in the role's colour with
#              its emblem seated at the bottom (trophy, heart, flask, shield)
#              and its own trim (stars, plus signs, a dashed ring, brackets)
#   Supporter  opal: a pearly band turning through lilac, periwinkle, mint
#              and peach, a gem heart beating at the bottom whose pulse runs
#              up both sides of the ring, little hearts drifting up round it
#   Prestige 1 / 10 / 100 / 1,000 / 10,000   bronze, silver, gold, diamond and
#              the rainbow, with one to five gems, points from gold on
#   Prestige 5 / 50 / 500 / 5,000   the steps between: copper with rivets and
#              a turquoise gem, rose gold with a ring of petals, emerald with
#              laurels, amethyst with a crown of crystals
#   Prestige 67   "six seven": a 6 and a 7 weighed up and down either side,
#              little sixes and sevens going round, two eyes on top that look
#              from one to the other
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
		"image_url": String(f.get("image_url", "")) if f.get("image_url") != null else "",
		"image_gif_url": String(f.get("image_gif_url", "")) if f.get("image_gif_url") != null else "",
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
		"image": _image(ci, c, r, fr)
		"ranker": _ranker(ci, c, r, fr, t)
		"contributor": _contributor(ci, c, r, fr, t)
		"tester": _tester(ci, c, r, fr, t)
		"mod": _mod(ci, c, r, fr, t)
		"supporter": _supporter(ci, c, r, fr, t)
		"prestige1": _prestige(ci, c, r, t, 0)
		"prestige10": _prestige(ci, c, r, t, 1)
		"prestige100": _prestige(ci, c, r, t, 2)
		"prestige1000": _prestige(ci, c, r, t, 3)
		"prestige10000": _prestige(ci, c, r, t, 4)
		"prestige5": _prestige_mid(ci, c, r, t, 0)
		"prestige50": _prestige_mid(ci, c, r, t, 1)
		"prestige500": _prestige_mid(ci, c, r, t, 2)
		"prestige5000": _prestige_mid(ci, c, r, t, 3)
		"prestige67": _sixseven(ci, c, r, t)
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
# (Every frame is made of these, worked out again each time it moves, so it is
# kept light: about one slice per 6 px of the outer edge, which stays round to
# a tenth of a pixel, and the triangles' order is made once for each size and
# kept; it used to be up to 180 slices, all made again every time.)
const MESH_IDX_KEY := "chromia_frame_mesh_idx"
static func _mesh_idx(seg: int, nr: int) -> PoolIntArray:
	if not Engine.has_meta(MESH_IDX_KEY):
		Engine.set_meta(MESH_IDX_KEY, {})
	var cache: Dictionary = Engine.get_meta(MESH_IDX_KEY)
	var key := seg * 16 + nr
	if cache.has(key):
		return cache[key]
	var idx := PoolIntArray()
	for s in seg:
		for k in nr - 1:
			var i0: int = s * nr + k
			idx.append(i0)
			idx.append(i0 + 1)
			idx.append(i0 + nr)
			idx.append(i0 + 1)
			idx.append(i0 + nr + 1)
			idx.append(i0 + nr)
	cache[key] = idx
	return idx

static func _mesh_ring(ci: CanvasItem, c: Vector2, radii: Array, alphas: Array, shades: Array, stops: Array, rot: float, a0: float = 0.0, a1: float = TAU):
	var span: float = abs(a1 - a0)
	var seg := int(clamp(float(radii[radii.size() - 1]) * span * 0.16, 12.0, 96.0))
	var nr := radii.size()
	var pts := PoolVector2Array()
	var cols := PoolColorArray()
	pts.resize((seg + 1) * nr)
	cols.resize((seg + 1) * nr)
	var one: bool = stops.size() == 1
	var w := 0
	for s in seg + 1:
		var a: float = a0 + (a1 - a0) * float(s) / float(seg)
		var base: Color = stops[0] if one else _conic(stops, a / TAU + rot)
		var d := Vector2(cos(a), sin(a))
		for k in nr:
			pts[w] = c + d * float(radii[k])
			var col := _shade(base, float(shades[k]))
			col.a = base.a * float(alphas[k])
			cols[w] = col
			w += 1
	VisualServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _mesh_idx(seg, nr), pts, cols)

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

# a picture frame: an admin's picture (FrameImages.gd), a square 2 x REACH
# times the avatar's radius wide, centred on it (the avatar covers its middle
# 1 / REACH, about 70 %)
# A moving frame (an animated upload) also has a GIF, image_gif_url: that one
# is shown once it has come and been decoded, the still picture until then.
static func _image(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary):
	var fi = load("res://scripts/ui/FrameImages.gd").instance()
	var tex = null
	var gif := String(fr.get("image_gif_url", ""))
	if gif != "":
		tex = fi.pic(gif)
	if tex == null:
		tex = fi.pic(String(fr.get("image_url", "")))
	if tex == null:
		return
	var s := r * REACH
	ci.draw_texture_rect(tex, Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), false)

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

# ------------------------------------------------------------------ the team
# (ranker, contributor, tester, moderator: the website draws the same,
# website/assets/frames.js)

static func _star5(p: Vector2, s: float, rot0: float = -PI / 2.0) -> PoolVector2Array:
	var pts := PoolVector2Array()
	for i in 10:
		pts.append(_pt(p, s * 0.42 if i % 2 == 1 else s, rot0 + i * TAU / 10.0))
	return pts

static func _line(ci: CanvasItem, pts: Array, col: Color, w: float):
	ci.draw_polyline(PoolVector2Array(pts), col, max(1.0, w), true)

# the seat an emblem sits in, at the bottom of the ring
static func _seat(ci: CanvasItem, c: Vector2, r: float, col: Color, dark: Color) -> Vector2:
	var p := Vector2(c.x, c.y + r * 1.1)
	ci.draw_circle(p, r * 0.3, _with_a(dark.darkened(0.2), 0.96))
	_band(ci, p, r * 0.27, r * 0.31, [col.lightened(0.35), col, col.darkened(0.3), col], 0.0, [0.2, 0.4, -0.2])
	return p

static func _role_base(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var metal := [col, col.lightened(0.45), col, col.darkened(0.35), col.lightened(0.2), col.darkened(0.2)]
	_glow(ci, c, r * 1.08, r * 0.2, [col], 0.3)
	_band(ci, c, r * 0.99, r * 1.12, metal, t * 0.04, [-0.3, 0.15, 0.3])
	_band(ci, c, r * 1.14, r * 1.165, [col.lightened(0.4)], 0.0, [0.0, 0.3, 0.0], 0.85)

static func _ranker(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	_role_base(ci, c, r, fr, t)
	# a wreath of stars over the top
	for i in 7:
		var a: float = deg2rad(-150.0 + i * 20.0)
		var k: float = 0.75 + 0.25 * sin(t * 1.6 + i * 0.9)
		var s: float = r * (0.085 + 0.045 * (1.0 - abs(i - 3) / 3.0)) * k
		var sp := _pt(c, r * 1.3, a)
		ci.draw_circle(sp, s * 1.5, _with_a(GOLD_MID, 0.18 * k))
		_gpoly(ci, _star5(sp, s), GOLD_TOP, GOLD_MID, GOLD_EDGE, 1.0)
	# the trophy
	var p := _seat(ci, c, r, col, fr.color2)
	var u := r * 0.2
	ci.draw_arc(p + Vector2(0, -u * 0.25), u * 0.72, -0.5, 0.5, 8, GOLD_MID, max(1.0, u * 0.16), true)
	ci.draw_arc(p + Vector2(0, -u * 0.25), u * 0.72, PI - 0.5, PI + 0.5, 8, GOLD_MID, max(1.0, u * 0.16), true)
	_gpoly(ci, PoolVector2Array([p + Vector2(-u * 0.6, -u * 0.75), p + Vector2(u * 0.6, -u * 0.75), p + Vector2(u * 0.45, -u * 0.05), p + Vector2(u * 0.14, u * 0.2),
		p + Vector2(u * 0.14, u * 0.48), p + Vector2(u * 0.46, u * 0.6), p + Vector2(u * 0.46, u * 0.8), p + Vector2(-u * 0.46, u * 0.8),
		p + Vector2(-u * 0.46, u * 0.6), p + Vector2(-u * 0.14, u * 0.48), p + Vector2(-u * 0.14, u * 0.2), p + Vector2(-u * 0.45, -u * 0.05)]), GOLD_TOP, GOLD_LOW, GOLD_EDGE, 1.0)
	ci.draw_circle(p + Vector2(-u * 0.22, -u * 0.45), u * 0.1, Color(1, 1, 1, 0.8))

static func _contributor(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	_role_base(ci, c, r, fr, t)
	# plus signs going round
	for i in 8:
		var a: float = i * TAU / 8.0 + t * 0.25
		if sin(a) > 0.82:
			continue # (not over the emblem)
		var pp := _pt(c, r * 1.27, a)
		var s: float = r * 0.06 * (0.8 + 0.2 * sin(t * 2.0 + i))
		var w: float = max(1.0, r * 0.03)
		ci.draw_line(pp - Vector2(s, 0), pp + Vector2(s, 0), col.lightened(0.35), w, true)
		ci.draw_line(pp - Vector2(0, s), pp + Vector2(0, s), col.lightened(0.35), w, true)
	# the heart
	var p := _seat(ci, c, r, col, fr.color2)
	var u: float = r * 0.2 * (1.0 + 0.06 * sin(t * 3.0))
	var pts := PoolVector2Array()
	for i in 24:
		var a: float = i * TAU / 24.0
		pts.append(Vector2(p.x + u * 0.05 * 16.0 * pow(sin(a), 3.0), p.y - u * 0.05 * (13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)) + u * 0.08))
	_gpoly(ci, pts, col.lightened(0.45), col.darkened(0.15), col.darkened(0.6), 1.0)
	ci.draw_circle(p + Vector2(-u * 0.32, -u * 0.32), u * 0.12, Color(1, 1, 1, 0.75))

static func _tester(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	_role_base(ci, c, r, fr, t)
	# a dashed ring turning
	for i in 16:
		var a: float = i * TAU / 16.0 + t * 0.15
		if sin(a + TAU / 64.0) > 0.84:
			continue
		_band(ci, c, r * 1.21, r * 1.25, [col.lightened(0.2)], 0.0, [0.0, 0.3, 0.0], 0.9, a, a + TAU / 32.0)
	# the flask, with its bubbles
	var p := _seat(ci, c, r, col, fr.color2)
	var u := r * 0.2
	var glass := col.lightened(0.75)
	ci.draw_colored_polygon(PoolVector2Array([p + Vector2(-u * 0.56, u * 0.68), p + Vector2(u * 0.56, u * 0.68), p + Vector2(u * 0.3, u * 0.12), p + Vector2(-u * 0.3, u * 0.12)]), _with_a(col, 0.95))
	_line(ci, [p + Vector2(-u * 0.2, -u * 0.75), p + Vector2(-u * 0.2, -u * 0.15), p + Vector2(-u * 0.66, u * 0.78), p + Vector2(u * 0.66, u * 0.78),
		p + Vector2(u * 0.2, -u * 0.15), p + Vector2(u * 0.2, -u * 0.75)], glass, u * 0.13)
	_line(ci, [p + Vector2(-u * 0.32, -u * 0.78), p + Vector2(u * 0.32, -u * 0.78)], glass, u * 0.13)
	for k in 3:
		var ph := fposmod(t * 0.55 + k * 0.33, 1.0)
		ci.draw_circle(Vector2(p.x + sin(k * 2.1 + t) * u * 0.14, p.y + u * 0.4 - ph * u * 1.7), u * (0.1 - 0.05 * ph), _with_a(col.lightened(0.5), 0.9 * (1.0 - ph)))

static func _mod(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	_role_base(ci, c, r, fr, t)
	# guard brackets at the four corners
	var p0: float = 0.75 + 0.25 * sin(t * 2.0)
	for i in 4:
		var a: float = PI / 4.0 + i * PI / 2.0
		if i == 0 or i == 1: # (the lower two are shorter: the emblem is between them)
			var off: float = -0.12 if i == 0 else 0.12
			_band(ci, c, r * 1.21, r * 1.26, [col.lightened(0.3)], 0.0, [0.1, 0.4, 0.0], 0.9 * p0, a - 0.2 + off, a + 0.2 + off)
		else:
			_band(ci, c, r * 1.21, r * 1.26, [col.lightened(0.3)], 0.0, [0.1, 0.4, 0.0], 0.9 * p0, a - 0.35, a + 0.35)
	# the shield with its tick
	var p := _seat(ci, c, r, col, fr.color2)
	var u := r * 0.2
	_gpoly(ci, PoolVector2Array([p + Vector2(0, -u * 0.82), p + Vector2(u * 0.66, -u * 0.55), p + Vector2(u * 0.62, u * 0.15), p + Vector2(u * 0.36, u * 0.58), p + Vector2(0, u * 0.85),
		p + Vector2(-u * 0.36, u * 0.58), p + Vector2(-u * 0.62, u * 0.15), p + Vector2(-u * 0.66, -u * 0.55)]), col.lightened(0.35), col.darkened(0.35), col.darkened(0.65), 1.0)
	_line(ci, [p + Vector2(-u * 0.3, u * 0.02), p + Vector2(-u * 0.06, u * 0.3), p + Vector2(u * 0.34, -u * 0.26)], Color(1, 1, 1, 0.95), max(1.2, u * 0.16))

# ------------------------------------------------------------------ prestige
# 1, 10, 100, 1,000 and 10,000: bronze, silver, gold, diamond, the rainbow
const PRESTIGE_METAL := [
	[Color("#f0b27a"), Color("#cd7f32"), Color("#8a4f1d"), Color("#e39a56"), Color("#a8641f"), Color("#f6c394")],
	[Color("#ffffff"), Color("#c8d2e0"), Color("#7d8896"), Color("#e9eef5"), Color("#9aa6b5"), Color("#f4f7fb")],
	[Color("#fff4c2"), Color("#f5c84c"), Color("#b8801e"), Color("#ffe08a"), Color("#d79b2b"), Color("#f9dc7a")],
	[Color("#e9fbff"), Color("#6fe3ff"), Color("#2a9fd0"), Color("#b8f3ff"), Color("#49c2ee"), Color("#ffffff")],
	[Color("#ff5e7a"), Color("#ffb347"), Color("#fff275"), Color("#6ef3a5"), Color("#5cc8ff"), Color("#b28dff"), Color("#ff7ad9")],
]
const PRESTIGE_GEM := [Color("#ffb347"), Color("#9ad0ff"), Color("#ff4d6a"), Color("#6fe3ff")]
const PRESTIGE_POINTS := [0, 0, 12, 16, 24]
const PRESTIGE_LEN := [0.0, 0.0, 0.08, 0.11, 0.14]

static func _prestige(ci: CanvasItem, c: Vector2, r: float, t: float, tier: int):
	var m: Array = PRESTIGE_METAL[tier]
	var spin: float = t * 0.12 if tier == 4 else t * 0.04
	_glow(ci, c, r * 1.08, r * (0.18 + tier * 0.06), m, 0.25 + tier * 0.08, spin)
	if tier == 4:
		_glow(ci, c, r * 1.1, r * 0.5, m, 0.3 + 0.1 * sin(t * 2.0), -spin)
	# points round the outside (from gold on)
	var np: int = PRESTIGE_POINTS[tier]
	for i in np:
		var a: float = i * TAU / np + (t * 0.1 if tier == 4 else 0.0)
		var lng: float = 1.0 if i % 2 == 0 else 0.6
		var col := _conic(m, a / TAU + spin)
		ci.draw_polygon(PoolVector2Array([_pt(c, r * 1.15, a - 0.07), _pt(c, r * (1.17 + float(PRESTIGE_LEN[tier]) * lng), a), _pt(c, r * 1.15, a + 0.07)]),
			PoolColorArray([col.darkened(0.15), col.lightened(0.5), col.darkened(0.15)]))
	_band(ci, c, r * 0.99, r * 1.12, m, spin, [-0.3, 0.2, 0.3])
	_band(ci, c, r * 1.135, r * 1.165, [m[1].lightened(0.35), m[1], m[1].lightened(0.55)], -spin, [0.2, 0.4, -0.1])
	_band(ci, c, r * 0.975, r * 1.0, [m[2].darkened(0.3)], 0.0, [0.0, 0.2, 0.0], 0.85)
	# twinkles (diamond and the rainbow)
	if tier >= 3:
		for s in SPARKS:
			var k: float = max(0.0, sin(t * 2.2 + float(s[1])))
			_twinkle(ci, _pt(c, r * (1.3 + 0.05 * sin(float(s[1]) * 3.0)), deg2rad(float(s[0]))), r * 0.15 * float(s[2]), _conic(m, float(s[0]) / 360.0 + spin), k)
	# one gem for each step: 1, 2, 3, 4, 5, along the bottom
	var n := tier + 1
	for i in n:
		var a: float = PI / 2.0 + (i - (n - 1) / 2.0) * 0.3
		var mid: bool = abs(i - (n - 1) / 2.0) < 0.6
		var gp := _pt(c, r * 1.065, a)
		var gs: float = r * (0.115 if mid else 0.085)
		ci.draw_circle(gp, gs * 1.25, _with_a(m[2].darkened(0.5), 0.95))
		_gem(ci, gp, gs, PRESTIGE_GEM[tier] if tier < 4 else m[i % m.size()])
	# the last one: a star on top
	if tier == 4:
		var sp := _pt(c, r * 1.3, -PI / 2.0)
		var k2: float = 0.85 + 0.15 * sin(t * 3.0)
		var sc := _conic(m, spin * 3.0)
		ci.draw_circle(sp, r * 0.2 * k2, _with_a(sc, 0.3))
		_gpoly(ci, _star5(sp, r * 0.17 * k2), Color(1, 1, 1, 1), sc, sc.darkened(0.5), 1.0)

# ------------------------------------------------------------------ prestige, the steps between
# 5, 50, 500 and 5,000: copper, rose gold, emerald, amethyst. Each has what its
# neighbours have (one to four gems, points from emerald on) and one thing of
# its own: rivets, petals, laurels, a crown of crystals.
const MID_METAL := [
	[Color("#ffc9a3"), Color("#d9793d"), Color("#8f3f17"), Color("#f0a06b"), Color("#b8562a"), Color("#ffd9bd")],
	[Color("#ffe3e0"), Color("#f4a6a0"), Color("#b76e79"), Color("#ffd1cc"), Color("#d98a8e"), Color("#fff0ee")],
	[Color("#eaffd9"), Color("#5fe08a"), Color("#1f8a52"), Color("#b6f5c8"), Color("#34b56f"), Color("#f5ffe9")],
	[Color("#f3e6ff"), Color("#b57bff"), Color("#5b2bb0"), Color("#dcc2ff"), Color("#8a4de0"), Color("#ffffff")],
]
const MID_GEM := [Color("#3fe0c5"), Color("#ff6fa8"), Color("#ffd23f"), Color("#ff7ad9")]
const MID_POINTS := [0, 0, 14, 20]
const MID_LEN := [0.0, 0.0, 0.095, 0.125]
const SHARDS := [0.15, 0.23, 0.33, 0.23, 0.15]

static func _prestige_mid(ci: CanvasItem, c: Vector2, r: float, t: float, k: int):
	var m: Array = MID_METAL[k]
	var g: float = k + 0.5 # (how rich: between the steps on either side of it)
	var spin: float = t * 0.04
	_glow(ci, c, r * 1.08, r * (0.18 + g * 0.06), m, 0.25 + g * 0.08, spin)
	# rose gold: a ring of petals round the outside
	if k == 1:
		for i in 18:
			var a: float = i * TAU / 18.0
			var p := _pt(c, r * 1.17, a)
			ci.draw_circle(p, r * 0.062, _with_a(m[2].darkened(0.25), 0.95))
			ci.draw_circle(p, r * 0.047, _conic(m, a / TAU + spin).lightened(0.12))
	# points round the outside (emerald and amethyst; the amethyst's uneven, like crystal)
	var np: int = MID_POINTS[k]
	for i in np:
		var a: float = i * TAU / np
		var lng: float = [1.0, 0.5, 0.75, 0.5][i % 4] if k == 3 else (1.0 if i % 2 == 0 else 0.6)
		var col := _conic(m, a / TAU + spin)
		ci.draw_polygon(PoolVector2Array([_pt(c, r * 1.15, a - 0.07), _pt(c, r * (1.17 + float(MID_LEN[k]) * lng), a), _pt(c, r * 1.15, a + 0.07)]),
			PoolColorArray([col.darkened(0.15), col.lightened(0.5), col.darkened(0.15)]))
	_band(ci, c, r * 0.99, r * 1.12, m, spin, [-0.3, 0.2, 0.3])
	_band(ci, c, r * 1.135, r * 1.165, [m[1].lightened(0.35), m[1], m[1].lightened(0.55)], -spin, [0.2, 0.4, -0.1])
	_band(ci, c, r * 0.975, r * 1.0, [m[2].darkened(0.3)], 0.0, [0.0, 0.2, 0.0], 0.85)
	# copper: rivets round the band (not where the gem sits)
	if k == 0:
		for i in 12:
			var a: float = i * TAU / 12.0 + PI / 12.0
			if abs(fposmod(a - PI / 2.0 + PI, TAU) - PI) < 0.4:
				continue
			var p := _pt(c, r * 1.055, a)
			ci.draw_circle(p, r * 0.032, m[2].darkened(0.4))
			ci.draw_circle(p, r * 0.024, m[4])
			ci.draw_circle(p - Vector2(r * 0.008, r * 0.008), r * 0.011, m[0])
	# emerald: laurels up both sides
	if k == 2:
		for side in [-1.0, 1.0]:
			for j in 5:
				var a: float = PI / 2.0 + side * (0.62 + j * 0.3)
				var p: Vector2 = _pt(c, r * 1.17, a)
				var out: Vector2 = (p - c).normalized()
				var along: Vector2 = Vector2(-out.y, out.x) * side # (up the ring, away from the bottom)
				var dir: Vector2 = (out * 0.5 + along).normalized()
				var w: Vector2 = Vector2(-dir.y, dir.x) * r * 0.045
				var tip: Vector2 = p + dir * r * 0.2
				ci.draw_polygon(PoolVector2Array([p, p + dir * r * 0.08 + w, tip, p + dir * r * 0.08 - w]),
					PoolColorArray([m[2].darkened(0.2), m[1], m[0], m[2]]))
	# amethyst: twinkles, and a crown of crystals on top
	if k == 3:
		for s in SPARKS:
			var tw: float = max(0.0, sin(t * 2.2 + float(s[1])))
			_twinkle(ci, _pt(c, r * (1.3 + 0.05 * sin(float(s[1]) * 3.0)), deg2rad(float(s[0]))), r * 0.13 * float(s[2]), _conic(m, float(s[0]) / 360.0 + spin), tw)
		for i in SHARDS.size():
			var a: float = -PI / 2.0 + (i - 2) * 0.21
			var glint: float = 0.5 + 0.5 * sin(t * 1.8 + i * 1.3)
			ci.draw_polygon(PoolVector2Array([_pt(c, r * 1.13, a - 0.085), _pt(c, r * (1.14 + float(SHARDS[i])), a), _pt(c, r * 1.13, a + 0.085)]),
				PoolColorArray([m[2], m[0].linear_interpolate(Color(1, 1, 1), glint * 0.6), m[4]]))
			ci.draw_polygon(PoolVector2Array([_pt(c, r * 1.13, a - 0.085), _pt(c, r * (1.14 + float(SHARDS[i])), a), _pt(c, r * 1.13, a - 0.01)]),
				PoolColorArray([_with_a(m[0], 0.0), _with_a(m[0], 0.55), _with_a(m[0], 0.15)]))
	# gems along the bottom: 1, 2, 3, 4
	var n := k + 1
	for i in n:
		var a: float = PI / 2.0 + (i - (n - 1) / 2.0) * 0.3
		var mid: bool = abs(i - (n - 1) / 2.0) < 0.6
		var gp := _pt(c, r * 1.065, a)
		var gs: float = r * (0.115 if mid else 0.085)
		ci.draw_circle(gp, gs * 1.25, _with_a(m[2].darkened(0.5), 0.95))
		_gem(ci, gp, gs, MID_GEM[k])

# ------------------------------------------------------------------ prestige 67
# "Six seven": a 6 on the left and a 7 on the right, one going up as the other
# goes down (the way it is said, with both hands), little sixes and sevens
# going round, and two eyes on top that look from the one to the other.
const SIXSEVEN := [Color("#7cff4f"), Color("#b45cff"), Color("#ffd23f"), Color("#ff5ac8")]
const SIX := [Vector2(0.42, -0.9), Vector2(0.05, -0.97), Vector2(-0.33, -0.62), Vector2(-0.5, -0.05), Vector2(-0.5, 0.45), Vector2(-0.3, 0.85), Vector2(0.0, 1.0),
	Vector2(0.3, 0.85), Vector2(0.5, 0.45), Vector2(0.33, 0.1), Vector2(0.0, -0.03), Vector2(-0.3, 0.1), Vector2(-0.48, 0.4)]
const SEVEN := [Vector2(-0.5, -0.95), Vector2(0.5, -0.95), Vector2(-0.08, 1.0)]

# a 6 or a 7 as a thick stroke with a dark edge (p: its middle, s: half its height)
static func _digit(ci: CanvasItem, shape: Array, p: Vector2, s: float, rot: float, col: Color):
	var pts := []
	for v in shape:
		pts.append(p + (v * s).rotated(rot))
	_line(ci, pts, Color(0.07, 0.04, 0.12, col.a), s * 0.66)
	_line(ci, pts, col, s * 0.36)

static func _sixseven(ci: CanvasItem, c: Vector2, r: float, t: float):
	var m: Array = SIXSEVEN
	var spin: float = t * 0.1
	var dark := Color(0.07, 0.04, 0.12)
	_glow(ci, c, r * 1.08, r * 0.3, m, 0.4, spin)
	_band(ci, c, r * 0.99, r * 1.12, m, spin, [-0.25, 0.25, 0.3])
	_band(ci, c, r * 1.135, r * 1.165, [m[0].lightened(0.45), m[2].lightened(0.3), m[3].lightened(0.4)], -spin, [0.2, 0.4, -0.1])
	_band(ci, c, r * 0.975, r * 1.0, [Color("#1a1030")], 0.0, [0.0, 0.2, 0.0], 0.85)
	# little sixes and sevens going round
	for i in 6:
		var a: float = i * TAU / 6.0 + t * 0.35
		var k: float = 0.55 + 0.45 * sin(t * 2.0 + i)
		_digit(ci, SIX if i % 2 == 0 else SEVEN, _pt(c, r * 1.33, a), r * 0.065, sin(t * 3.0 + i) * 0.3, _with_a(m[i % m.size()], k))
	# the two being weighed: the 6 on the left, the 7 on the right
	var bob: float = sin(t * 6.0)
	var lp := _pt(c, r * 1.12, PI * 0.83) + Vector2(0, -bob * r * 0.1)
	var rp := _pt(c, r * 1.12, PI * 0.17) + Vector2(0, bob * r * 0.1)
	ci.draw_circle(lp, r * 0.2, dark)
	ci.draw_circle(lp, r * 0.175, m[1])
	ci.draw_circle(rp, r * 0.2, dark)
	ci.draw_circle(rp, r * 0.175, m[3])
	_digit(ci, SIX, lp, r * 0.115, -0.12 - bob * 0.14, Color(1, 1, 1))
	_digit(ci, SEVEN, rp, r * 0.115, 0.12 - bob * 0.14, Color(1, 1, 1))
	# two eyes on top, looking from the one to the other
	for side in [-1.0, 1.0]:
		var e: Vector2 = _pt(c, r * 1.1, -PI / 2.0 + side * 0.21)
		ci.draw_circle(e, r * 0.09, dark)
		ci.draw_circle(e, r * 0.074, Color(1, 1, 1))
		ci.draw_circle(e + Vector2(bob * r * 0.032, r * 0.012), r * 0.036, dark)

# ------------------------------------------------------------------ Supporter

# opal: soft lilac, periwinkle, mint and peach (not Valentine's reds)
const OPAL := [Color("#c9a7ff"), Color("#9db8ff"), Color("#9ff0d0"), Color("#ffd29d")]
const BEAT := 1.5 # seconds between heartbeats

# a heart's outline around p, s about its half width, turned by rot
static func heart_pts(p: Vector2, s: float, rot: float = 0.0, n: int = 24) -> PoolVector2Array:
	var pts := PoolVector2Array()
	var k := s / 16.0
	for i in n:
		var a: float = i * TAU / float(n)
		var v := Vector2(16.0 * pow(sin(a), 3.0), -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)) - 1.5) * k
		pts.append(p + v.rotated(rot))
	return pts

# the heartbeat: a strong beat, then a softer one (0..about 1)
static func beat(t: float) -> float:
	var ph: float = fposmod(t, BEAT) / BEAT
	return exp(-pow((ph - 0.03) / 0.05, 2.0)) + 0.6 * exp(-pow((ph - 0.21) / 0.055, 2.0))

static func _supporter(ci: CanvasItem, c: Vector2, r: float, fr: Dictionary, t: float):
	var col: Color = fr.color
	var dark: Color = fr.color2
	var b := beat(t)
	var ph: float = fposmod(t, BEAT) / BEAT
	var turn: float = t * 0.05
	# a soft opal glow that swells with each beat
	_glow(ci, c, r * 1.08, r * 0.24, OPAL, 0.2 + 0.16 * b, turn)
	# the opal band, slowly turning, with a pearl rim outside it
	var pearl := []
	for o in OPAL:
		pearl.append(o.linear_interpolate(Color(1, 1, 1), 0.18))
	_band(ci, c, r * 0.99, r * 1.1, pearl, turn, [-0.28, 0.18, 0.22])
	_band(ci, c, r * 1.122, r * 1.142, [Color(1, 1, 1)], 0.0, [0.0, 0.0, 0.0], 0.45 + 0.2 * b)
	# the pulse: from the heart at the bottom, up both sides, meeting at the top
	if ph < 0.62:
		var s: float = ph / 0.62
		var reach: float = s * PI
		var fade: float = (1.0 - s) * (1.0 - s)
		for side in [-1.0, 1.0]:
			var head: float = PI / 2.0 + side * reach
			for k in 4:
				var a: float = head - side * k * 0.09
				var w: float = 0.08
				_band(ci, c, r * 0.985, r * 1.115, [Color(1, 1, 1)], 0.0, [0.2, 0.45, 0.2], fade * (0.95 - k * 0.2), a - w, a + w)
	# little hearts drifting up round the outside, three a side
	for i in 6:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var u: float = fposmod(t / 4.8 + float(i) / 6.0, 1.0)
		var a: float = PI / 2.0 - side * (0.5 + u * (PI - 0.95))
		var rad: float = r * (1.29 + 0.035 * sin(t * 2.2 + i * 1.3))
		var hp := _pt(c, rad, a)
		var life: float = sin(u * PI)
		var hs: float = r * 0.07 * (0.55 + 0.45 * life)
		var hc := _conic(OPAL, float(i) * 0.23 + t * 0.08)
		var tilt: float = side * 0.25 * sin(t * 1.7 + i)
		ci.draw_circle(hp, hs * 1.3, _with_a(hc, 0.14 * life))
		_gpoly(ci, heart_pts(hp, hs, tilt, 20), _with_a(hc.lightened(0.45), life), _with_a(hc, life))
	# twinkles on the band
	for i in 3:
		var k2: float = max(0.0, sin(t * 1.25 + i * 2.1))
		_twinkle(ci, _pt(c, r * 1.06, -PI / 2.0 + (i - 1) * 1.05 + sin(t * 0.3 + i) * 0.2), r * 0.075, col, k2 * k2)
	# the heart, beating, sitting on the ring at the bottom
	var p := Vector2(c.x, c.y + r * 1.1)
	var u2: float = r * 0.25 * (1.0 + 0.11 * b)
	var top := _conic(OPAL, t * 0.07).lightened(0.15)
	var bottom := _conic(OPAL, t * 0.07 + 0.4).darkened(0.22)
	# (a ring of light leaving it on each beat)
	var wave: float = clamp(ph / 0.7, 0.0, 1.0)
	if wave < 1.0:
		var wo := heart_pts(p, u2 * (1.0 + wave * 1.3), 0.0, 28)
		wo.append(wo[0])
		ci.draw_polyline(wo, _with_a(top, (1.0 - wave) * (1.0 - wave) * 0.75), max(1.0, r * 0.03), true)
	ci.draw_circle(p, u2 * 1.35, _with_a(dark.darkened(0.2), 0.5))
	ci.draw_circle(p, u2 * 1.2, _with_a(top, 0.12 + 0.18 * b))
	_gpoly(ci, heart_pts(p, u2, 0.0, 28), top, bottom, dark.darkened(0.35), max(1.0, r * 0.025))
	# a facet and a shine, so it reads as a gem
	_gpoly(ci, heart_pts(p + Vector2(0, -u2 * 0.12), u2 * 0.62, 0.0, 24), _with_a(Color(1, 1, 1), 0.2), _with_a(Color(1, 1, 1), 0.0))
	ci.draw_circle(p + Vector2(-u2 * 0.42, -u2 * 0.38), u2 * 0.13, Color(1, 1, 1, 0.85))
	_twinkle(ci, p + Vector2(u2 * 0.55, -u2 * 0.62), u2 * 0.32, top, b * 0.9)
