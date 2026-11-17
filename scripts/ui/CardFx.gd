extends Control

# A moving card (the server's card "fx", src/cards.js), drawn behind a card's
# name and picture in the Spectate grid (SpectatePage.gd) and profile > Cards
# (CardsMenu.gd):
#   hearts   Supporter: opal hearts drifting up, a soft glow breathing at the
#            bottom, and two lights running round the border
# With no fx it draws nothing and doesn't run.

const FD := preload("res://scripts/ui/FrameDraw.gd")
const HEARTS := 9

var fx := ""
var inset := 0.0 # (how far in from this control's edge the card's border is)

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process(fx != "")

func set_fx(name: String):
	fx = name if name == "hearts" else ""
	visible = fx != ""
	set_process(fx != "")
	update()

func _process(_d):
	if is_visible_in_tree():
		update()

func _draw():
	if fx == "hearts":
		draw_hearts(self, Rect2(Vector2.ZERO, rect_size), OS.get_ticks_msec() / 1000.0, inset)

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
