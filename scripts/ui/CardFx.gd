extends Control

# A moving card (the server's card "fx", src/cards.js CARD_FX), drawn behind a
# card's name and picture in the Spectate grid (SpectatePage.gd) and profile >
# Cards (CardsMenu.gd). Everything but the hearts takes the card's border
# colour (`color`):
#   hearts   Supporter: opal hearts drifting up, a soft glow breathing at the
#            bottom, and two lights running round the border
#   royal    Admin: gold sparks rising, a slow gold sheen, gold lights
#   code     Developer: columns of bits falling, a scan line
#   bars     DJ: sound bars jumping along the bottom
#   stars    Ranker: stars twinkling and drifting up, a sheen
#   plus     Contributor: plus signs floating up and turning
#   bubbles  Tester: bubbles rising and popping
#   guard    Moderator: rings spreading out, a light sweeping round the border
#   shine1-5 Prestige: a metal sheen with more glints and border lights each
#            step; the fifth in every colour
# With no fx (or one this game doesn't know) it draws nothing and doesn't run.

const FD := preload("res://scripts/ui/FrameDraw.gd")
const HEARTS := 9
const KNOWN := ["hearts", "royal", "code", "bars", "stars", "plus", "bubbles", "guard", "shine1", "shine2", "shine3", "shine4", "shine5"]
const GOLD := Color("#ffd76a")

var fx := ""
var color := Color(0.78, 0.65, 1.0)
var inset := 0.0 # (how far in from this control's edge the card's border is)

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	rect_clip_content = true # (rings and sparks stay on the card)
	set_process(fx != "")

func set_fx(name: String, col = null):
	fx = name if name in KNOWN else ""
	if col is Color:
		color = col
	visible = fx != ""
	set_process(fx != "")
	update()

func _process(_d):
	if is_visible_in_tree():
		update()

func _draw():
	if fx == "":
		return
	var rect := Rect2(Vector2.ZERO, rect_size)
	var t: float = OS.get_ticks_msec() / 1000.0
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	match fx:
		"hearts":
			draw_hearts(self, rect, t, inset)
		"royal":
			_glow_bottom(self, rect, Color("#ff4d6a").linear_interpolate(GOLD, 0.5 + 0.5 * sin(t * 0.7)), 0.13 + 0.05 * sin(t * 1.1))
			_sparks(self, rect, t, 10, GOLD, true)
			_sheen(self, rect, t, GOLD, 5.5)
			_lights(self, rect, t, inset, [GOLD, GOLD.lightened(0.4)], 2, 0.12)
		"code":
			_rain(self, rect, t, color)
			_scan(self, rect, t, color.lightened(0.3), 4.0)
			_lights(self, rect, t, inset, [color.lightened(0.3)], 1, 0.16)
		"bars":
			_bars(self, rect, t, color)
		"stars":
			_glow_bottom(self, rect, color, 0.08 + 0.03 * sin(t * 1.3))
			_sparks(self, rect, t, 9, color.lightened(0.35), true)
			_twinkles(self, rect, t, 5, Color(1, 1, 1))
			_sheen(self, rect, t, color.lightened(0.5), 6.5)
		"plus":
			_pluses(self, rect, t, color)
			_lights(self, rect, t, inset, [color.lightened(0.3)], 1, 0.1)
		"bubbles":
			_glow_bottom(self, rect, color, 0.10 + 0.03 * sin(t * 1.7))
			_bubbles(self, rect, t, color)
		"guard":
			_rings(self, rect, t, color)
			_lights(self, rect, t, inset, [color.lightened(0.45)], 1, 0.22)
		_:
			var step := int(fx.substr(5)) if fx.begins_with("shine") else 1
			_shine(self, rect, t, inset, color, step)

# a steady "random" number for heart i (0..1)
static func _h(i: int, k: int) -> float:
	return fposmod(sin(i * 12.9898 + k * 78.233) * 43758.5453, 1.0)

static func draw_hearts(ci: CanvasItem, rect: Rect2, t: float, inset: float = 0.0):
	var w := rect.size.x
	var h := rect.size.y
	if w < 8.0 or h < 8.0:
		return
	# a glow breathing at the bottom, in the opal colours going round
	var glow: Color = FD._conic(FD.OPAL, t * 0.05)
	var ga: float = 0.15 + 0.06 * sin(t * 1.3) + 0.05 * FD.beat(t)
	var clear := Color(glow.r, glow.g, glow.b, 0.0)
	ci.draw_polygon(PoolVector2Array([rect.position + Vector2(0, h * 0.4), rect.position + Vector2(w, h * 0.4), rect.end, rect.position + Vector2(0, h)]),
		PoolColorArray([clear, clear, Color(glow.r, glow.g, glow.b, ga), Color(glow.r, glow.g, glow.b, ga)]))
	# hearts rising, each at its own pace, swaying, fading in and out
	var m: float = min(w, h)
	for i in HEARTS:
		var period: float = 5.5 + 3.0 * _h(i, 1)
		var u: float = fposmod(t / period + _h(i, 2), 1.0)
		var s: float = m * (0.028 + 0.034 * _h(i, 5))
		var x: float = rect.position.x + w * (0.08 + 0.84 * _h(i, 3)) + sin(t * (0.8 + _h(i, 4)) + i) * w * 0.03
		var y: float = rect.end.y + s * 2.0 - (h + s * 4.0) * u
		var a: float = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.55, 1.0, u)) * (0.5 + 0.3 * _h(i, 6))
		if a <= 0.01 or s < 1.5:
			continue
		var hc: Color = FD._conic(FD.OPAL, _h(i, 7) + t * 0.06).lightened(0.15)
		var tilt: float = sin(t * 1.1 + i * 1.7) * 0.35
		var p := Vector2(x, y)
		FD._gpoly(ci, FD.heart_pts(p, s, tilt, 20), Color(1, 1, 1, a).linear_interpolate(Color(hc.r, hc.g, hc.b, a), 0.35), Color(hc.r, hc.g, hc.b, a * 0.85))
		if i % 3 == 0:
			FD._star4(ci, p + Vector2(s * 1.2, -s * 1.1), s * 0.5 * (0.5 + 0.5 * sin(t * 3.0 + i)), Color(1, 1, 1, a * 1.6))
	# two lights running round the border, opposite each other
	var r := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	var per: float = 2.0 * (r.size.x + r.size.y)
	for k in 2:
		var head: float = fposmod(t * 0.14 + k * 0.5, 1.0) * per
		var pts := PoolVector2Array()
		var cols := PoolColorArray()
		var n := 14
		var tail: float = per * 0.2
		var lc: Color = FD._conic(FD.OPAL, t * 0.05 + k * 0.5).lightened(0.35)
		for j in n + 1:
			var f: float = float(j) / float(n)
			pts.append(_on_rect(r, fposmod(head - tail * (1.0 - f), per)))
			cols.append(Color(lc.r, lc.g, lc.b, f * f).lightened(f * f * 0.5))
		ci.draw_polyline_colors(pts, cols, 2.5, true)

# the point a distance d round the rectangle's edge (clockwise from the top left)
static func _on_rect(r: Rect2, d: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	if d < w:
		return r.position + Vector2(d, 0)
	d -= w
	if d < h:
		return r.position + Vector2(w, d)
	d -= h
	if d < w:
		return r.position + Vector2(w - d, h)
	d -= w
	return r.position + Vector2(0, h - min(d, h))

# ------------------------------------------------------------------ the parts

# a glow at the bottom, fading out upwards
static func _glow_bottom(ci: CanvasItem, rect: Rect2, col: Color, alpha: float):
	var w := rect.size.x
	var h := rect.size.y
	var clear := Color(col.r, col.g, col.b, 0.0)
	var full := Color(col.r, col.g, col.b, alpha)
	ci.draw_polygon(PoolVector2Array([rect.position + Vector2(0, h * 0.4), rect.position + Vector2(w, h * 0.4), rect.end, rect.position + Vector2(0, h)]),
		PoolColorArray([clear, clear, full, full]))

# lights running round the border, evenly apart (cols: one colour each, used in turn)
static func _lights(ci: CanvasItem, rect: Rect2, t: float, inset: float, cols: Array, count: int, speed: float):
	var r := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
	var per: float = 2.0 * (r.size.x + r.size.y)
	if per <= 0.0:
		return
	for k in count:
		var head: float = fposmod(t * speed + float(k) / float(count), 1.0) * per
		var pts := PoolVector2Array()
		var pc := PoolColorArray()
		var n := 12
		var tail: float = per * 0.18
		var lc: Color = cols[k % cols.size()]
		for j in n + 1:
			var f: float = float(j) / float(n)
			pts.append(_on_rect(r, fposmod(head - tail * (1.0 - f), per)))
			pc.append(Color(lc.r, lc.g, lc.b, f * f))
		ci.draw_polyline_colors(pts, pc, 2.5, true)

# a slanted band of light crossing the card once every `period` seconds
static func _sheen(ci: CanvasItem, rect: Rect2, t: float, col: Color, period: float):
	var u: float = fposmod(t / period, 1.0)
	if u > 0.45:
		return # (it crosses in under half the time, then rests)
	var w := rect.size.x
	var h := rect.size.y
	var band: float = w * 0.16
	var slant: float = h * 0.5
	var x: float = rect.position.x - band - slant + (w + 2.0 * band + slant) * (u / 0.45)
	var y0 := rect.position.y
	var y1 := rect.end.y
	var mid := Color(col.r, col.g, col.b, 0.22)
	var edge := Color(col.r, col.g, col.b, 0.0)
	ci.draw_polygon(PoolVector2Array([Vector2(x + slant, y0), Vector2(x + slant + band, y0), Vector2(x + band, y1), Vector2(x, y1)]),
		PoolColorArray([edge, mid, mid, edge]))
	ci.draw_polygon(PoolVector2Array([Vector2(x + slant + band, y0), Vector2(x + slant + 2.0 * band, y0), Vector2(x + 2.0 * band, y1), Vector2(x + band, y1)]),
		PoolColorArray([mid, edge, edge, mid]))

# little four-pointed stars rising (drift) or staying where they are, each at its own pace
static func _sparks(ci: CanvasItem, rect: Rect2, t: float, n: int, col: Color, drift: bool):
	var w := rect.size.x
	var h := rect.size.y
	var m: float = min(w, h)
	for i in n:
		var period: float = 4.5 + 3.5 * _h(i, 11)
		var u: float = fposmod(t / period + _h(i, 12), 1.0)
		var s: float = m * (0.035 + 0.04 * _h(i, 13)) * (0.6 + 0.4 * sin(t * (2.0 + 2.0 * _h(i, 14)) + i))
		var x: float = rect.position.x + w * (0.06 + 0.88 * _h(i, 15)) + sin(t * (0.7 + _h(i, 16)) + i) * w * 0.02
		var y: float = rect.end.y + s - (h + 2.0 * s) * u if drift else rect.position.y + h * (0.1 + 0.8 * _h(i, 17))
		var a: float = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.6, 1.0, u)) * (0.45 + 0.4 * _h(i, 18))
		if a > 0.02:
			FD._star4(ci, Vector2(x, y), s, Color(col.r, col.g, col.b, a))

# glints that stay put and wink
static func _twinkles(ci: CanvasItem, rect: Rect2, t: float, n: int, col: Color):
	var m: float = min(rect.size.x, rect.size.y)
	for i in n:
		var ph: float = fposmod(t / (2.2 + 2.0 * _h(i, 21)) + _h(i, 22), 1.0)
		var a: float = max(0.0, sin(ph * PI)) # (in and out once a turn)
		a = a * a * a
		if a < 0.03:
			continue
		var p := rect.position + Vector2(rect.size.x * (0.08 + 0.84 * _h(i, 23)), rect.size.y * (0.12 + 0.76 * _h(i, 24)))
		FD._star4(ci, p, m * (0.05 + 0.05 * _h(i, 25)) * (0.5 + 0.5 * a), Color(col.r, col.g, col.b, a * 0.9))

# columns of bits falling: a bright head and a fading tail of small squares
static func _rain(ci: CanvasItem, rect: Rect2, t: float, col: Color):
	var w := rect.size.x
	var h := rect.size.y
	var cols := int(clamp(w / 22.0, 4, 14))
	var cell: float = max(3.0, min(w / cols * 0.32, h * 0.07))
	var gap: float = cell * 1.9
	for c in cols:
		var period: float = 2.6 + 2.8 * _h(c, 31)
		var u: float = fposmod(t / period + _h(c, 32), 1.0)
		var x: float = rect.position.x + (c + 0.5) * w / cols - cell * 0.5
		var head_y: float = rect.position.y - gap + (h + 7.0 * gap) * u
		for k in 6:
			var y: float = head_y - k * gap
			if y < rect.position.y - cell or y > rect.end.y:
				continue
			# (which bits are "on" changes as they fall: 0s are hollow, 1s filled)
			var on: bool = _h(c * 7 + k + int(floor(t * 3.0 + c)), 33) > 0.45
			var a: float = (0.75 if k == 0 else 0.42 * (1.0 - k / 6.0))
			var cc: Color = (col.lightened(0.5) if k == 0 else col)
			cc.a = a
			if on:
				ci.draw_rect(Rect2(x, y, cell, cell), cc)
			else:
				ci.draw_rect(Rect2(x, y, cell, cell), cc, false, 1.0)

# a thin bright line moving down the card
static func _scan(ci: CanvasItem, rect: Rect2, t: float, col: Color, period: float):
	var u: float = fposmod(t / period, 1.0)
	var y: float = rect.position.y + rect.size.y * u
	var a: float = 0.28 * sin(u * PI)
	ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(col.r, col.g, col.b, a), 1.5)
	var clear := Color(col.r, col.g, col.b, 0.0)
	var trail: float = rect.size.y * 0.12
	ci.draw_polygon(PoolVector2Array([Vector2(rect.position.x, y - trail), Vector2(rect.end.x, y - trail), Vector2(rect.end.x, y), Vector2(rect.position.x, y)]),
		PoolColorArray([clear, clear, Color(col.r, col.g, col.b, a * 0.35), Color(col.r, col.g, col.b, a * 0.35)]))

# sound bars along the bottom, moving like music
static func _bars(ci: CanvasItem, rect: Rect2, t: float, col: Color):
	var w := rect.size.x
	var h := rect.size.y
	var n := int(clamp(w / 14.0, 8, 22))
	var bw: float = w / n
	var kick: float = FD.beat(t * 1.6) # (a beat it moves to)
	for i in n:
		var v: float = 0.5 + 0.5 * sin(t * (3.1 + 2.3 * _h(i, 41)) + i * 1.3)
		v = 0.18 + 0.5 * v * (0.55 + 0.45 * sin(t * 1.7 + i * 0.6)) + 0.25 * kick * _h(i, 42)
		var bh: float = h * 0.55 * clamp(v, 0.05, 1.0)
		var top := Color(col.r, col.g, col.b, 0.5).lightened(0.25)
		var bot := Color(col.r, col.g, col.b, 0.12)
		var x0: float = rect.position.x + i * bw + bw * 0.15
		var x1: float = x0 + bw * 0.7
		ci.draw_polygon(PoolVector2Array([Vector2(x0, rect.end.y - bh), Vector2(x1, rect.end.y - bh), Vector2(x1, rect.end.y), Vector2(x0, rect.end.y)]),
			PoolColorArray([top, top, bot, bot]))

# plus signs floating up, turning
static func _pluses(ci: CanvasItem, rect: Rect2, t: float, col: Color):
	var w := rect.size.x
	var h := rect.size.y
	var m: float = min(w, h)
	for i in 8:
		var period: float = 6.0 + 3.0 * _h(i, 51)
		var u: float = fposmod(t / period + _h(i, 52), 1.0)
		var s: float = m * (0.05 + 0.045 * _h(i, 53))
		var p := Vector2(rect.position.x + w * (0.08 + 0.84 * _h(i, 54)) + sin(t * 0.9 + i) * w * 0.025, rect.end.y + s - (h + 2.0 * s) * u)
		var a: float = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.6, 1.0, u)) * (0.35 + 0.3 * _h(i, 55))
		if a <= 0.02:
			continue
		var rot: float = t * (0.4 + 0.5 * _h(i, 56)) * (1.0 if i % 2 == 0 else -1.0)
		var ax := Vector2(cos(rot), sin(rot)) * s
		var ay := Vector2(-ax.y, ax.x)
		var cc := Color(col.r, col.g, col.b, a)
		ci.draw_line(p - ax, p + ax, cc, max(1.5, s * 0.34), true)
		ci.draw_line(p - ay, p + ay, cc, max(1.5, s * 0.34), true)

# bubbles rising, swelling, gone near the top with a little burst
static func _bubbles(ci: CanvasItem, rect: Rect2, t: float, col: Color):
	var w := rect.size.x
	var h := rect.size.y
	var m: float = min(w, h)
	for i in 10:
		var period: float = 4.0 + 3.5 * _h(i, 61)
		var u: float = fposmod(t / period + _h(i, 62), 1.0)
		var top: float = 0.55 + 0.4 * _h(i, 63) # (how far up it gets before it pops)
		var r: float = m * (0.03 + 0.045 * _h(i, 64)) * (0.6 + 0.6 * u)
		var p := Vector2(rect.position.x + w * (0.08 + 0.84 * _h(i, 65)) + sin(t * (1.1 + _h(i, 66)) + i * 2.0) * w * 0.02, rect.end.y + r - (h + 2.0 * r) * u)
		if u < top:
			var a: float = smoothstep(0.0, 0.1, u) * (0.4 + 0.3 * _h(i, 67))
			ci.draw_arc(p, r, 0.0, TAU, 18, Color(col.r, col.g, col.b, a), 1.5, true)
			ci.draw_circle(p + Vector2(-r * 0.35, -r * 0.35), max(1.0, r * 0.18), Color(1, 1, 1, a * 0.8))
		elif u < top + 0.05:
			# the pop: short lines flying out
			var f: float = (u - top) / 0.05
			for k in 6:
				var d := Vector2(cos(k * TAU / 6.0), sin(k * TAU / 6.0))
				ci.draw_line(p + d * r * (1.0 + f), p + d * r * (1.5 + 1.2 * f), Color(col.r, col.g, col.b, 0.7 * (1.0 - f)), 1.5, true)

# rings spreading out from the middle
static func _rings(ci: CanvasItem, rect: Rect2, t: float, col: Color):
	var c := rect.position + rect.size / 2.0
	var far: float = rect.size.length() * 0.55
	for k in 3:
		var u: float = fposmod(t / 3.6 + k / 3.0, 1.0)
		var a: float = 0.32 * (1.0 - u) * smoothstep(0.0, 0.1, u)
		if a > 0.01:
			ci.draw_arc(c, far * u, 0.0, TAU, 40, Color(col.r, col.g, col.b, a), 2.0, true)

# Prestige: a sheen, glints and border lights, more of each with every step
static func _shine(ci: CanvasItem, rect: Rect2, t: float, inset: float, col: Color, step: int):
	step = int(clamp(step, 1, 5))
	var rainbow := step >= 5
	var c1: Color = Color.from_hsv(fposmod(t * 0.08, 1.0), 0.55, 1.0) if rainbow else col.lightened(0.45)
	_glow_bottom(ci, rect, c1 if rainbow else col, 0.06 + 0.02 * step + 0.02 * sin(t * 1.2))
	_sheen(ci, rect, t, c1, 7.5 - step * 0.8)
	if rainbow:
		for i in 9:
			var hc := Color.from_hsv(fposmod(_h(i, 71) + t * 0.1, 1.0), 0.5, 1.0)
			var ph: float = fposmod(t / (2.0 + 2.0 * _h(i, 72)) + _h(i, 73), 1.0)
			var a: float = pow(max(0.0, sin(ph * PI)), 3.0)
			if a > 0.03:
				var p := rect.position + Vector2(rect.size.x * (0.08 + 0.84 * _h(i, 74)), rect.size.y * (0.12 + 0.76 * _h(i, 75)))
				FD._star4(ci, p, min(rect.size.x, rect.size.y) * (0.06 + 0.05 * _h(i, 76)) * (0.5 + 0.5 * a), Color(hc.r, hc.g, hc.b, a))
		_sparks(ci, rect, t, 6, Color(1, 1, 1), true)
		_lights(ci, rect, t, inset, [Color.from_hsv(fposmod(t * 0.1, 1.0), 0.6, 1.0), Color.from_hsv(fposmod(t * 0.1 + 0.33, 1.0), 0.6, 1.0), Color.from_hsv(fposmod(t * 0.1 + 0.66, 1.0), 0.6, 1.0)], 3, 0.16)
	else:
		_twinkles(ci, rect, t, 2 + step * 2, Color(1, 1, 1).linear_interpolate(col, 0.25))
		if step >= 3:
			_lights(ci, rect, t, inset, [c1], step - 2, 0.1 + 0.02 * step)
		if step >= 4:
			_sparks(ci, rect, t, 5, c1, true)
