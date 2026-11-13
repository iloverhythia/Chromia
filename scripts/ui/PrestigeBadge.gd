extends Reference

# The prestige badge: one of its own for each of the 10,000 prestiges
# (scripts/PlayerLevel.gd), drawn from the number, so none has to be stored.
# Each digit of the prestige changes one thing:
#   the last digit   -> the colour (ten of them, the ones prestige 1-10 had)
#   the tens         -> dots inside (none to nine)
#   the hundreds     -> the shape (hexagon, diamond, pentagon, heptagon,
#                       octagon, three stars, shield, circle)
#   the thousands    -> spikes round the outside (none to nine)
# Prestige 0 is the plain grey hexagon; 10,000, the last, is the Chromia note
# in all its colours with a full ring of spikes.
# The website draws the same badge (savia_web: website/assets/savia.js).

const GREY := Color(0.45, 0.42, 0.5)
const COLORS := [
	Color(0.55, 0.85, 1.0), Color(0.5, 1.0, 0.65), Color(1.0, 0.92, 0.45), Color(1.0, 0.65, 0.35),
	Color(1.0, 0.45, 0.45), Color(1.0, 0.5, 0.85), Color(0.75, 0.55, 1.0), Color(0.5, 0.6, 1.0),
	Color(0.6, 1.0, 1.0), Color(1.0, 1.0, 1.0),
]
# the logo's colours, round the note (prestige 10,000)
const RAINBOW := [Color("#8fb6ff"), Color("#b98cf5"), Color("#f587b4"), Color("#f7a08c"), Color("#e6dc7e"), Color("#b4f07a")]
const SHAPE_NAMES := ["hexagon", "diamond", "pentagon", "heptagon", "octagon", "five-point star", "six-point star", "eight-point star", "shield", "circle"]
const LAST := 10000

static func color(prestige: int) -> Color:
	if prestige <= 0:
		return GREY
	if prestige >= LAST:
		return Color(1, 1, 1)
	return COLORS[(prestige - 1) % 10]

static func describe(prestige: int) -> String:
	if prestige <= 0:
		return "No prestige yet"
	if prestige >= LAST:
		return "Prestige 10,000: the Chromia note. There is none higher."
	return "Prestige %s badge: %s" % [_commas(prestige), SHAPE_NAMES[(prestige / 100) % 10]]

static func _commas(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)

# the outline of shape `kind` round c, radius r (closed: the first point again)
static func outline(kind: int, c: Vector2, r: float) -> PoolVector2Array:
	var pts := PoolVector2Array()
	var sides := 0
	var inner := 0.0 # (stars: the inner points, as a share of r)
	var turn := -PI / 2.0
	match kind:
		0:
			sides = 6
			turn = PI / 6.0
		1: sides = 4
		2: sides = 5
		3: sides = 7
		4:
			sides = 8
			turn = PI / 8.0
		5:
			sides = 5
			inner = 0.5
		6:
			sides = 6
			inner = 0.6
		7:
			sides = 8
			inner = 0.68
		8:
			# shield
			for q in [Vector2(0, -1), Vector2(0.86, -0.72), Vector2(0.86, 0.05), Vector2(0.62, 0.6), Vector2(0, 1), Vector2(-0.62, 0.6), Vector2(-0.86, 0.05), Vector2(-0.86, -0.72), Vector2(0, -1)]:
				pts.append(c + q * r)
			return pts
		_:
			sides = 28 # circle
	if inner > 0.0:
		for i in range(sides * 2 + 1):
			var a: float = turn + i * PI / float(sides)
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * inner))
	else:
		for i in range(sides + 1):
			var a2: float = turn + i * TAU / float(sides)
			pts.append(c + Vector2(cos(a2), sin(a2)) * r)
	return pts

# Draws the badge of `prestige` on `ci`, centred on c, within radius rad.
static func draw(ci: CanvasItem, c: Vector2, rad: float, prestige: int):
	prestige = int(clamp(prestige, 0, LAST))
	var col: Color = color(prestige)
	var line: float = max(1.5, rad * 0.22)
	if prestige >= LAST:
		_draw_last(ci, c, rad, line)
		return
	var spikes: int = prestige / 1000
	var body: float = rad if spikes == 0 else rad * 0.76
	var kind: int = (prestige / 100) % 10
	var pts := outline(kind, c, body - line * 0.5)
	if prestige > 0:
		var fill := pts
		fill.remove(fill.size() - 1)
		ci.draw_colored_polygon(fill, Color(col.r, col.g, col.b, 0.25))
	var edge := pts
	edge.append(pts[1]) # (once more round the first corner: the line closes cleanly there)
	ci.draw_polyline(edge, col, line, true)
	# the tens: dots in a ring inside (one sits in the middle)
	var dots: int = (prestige / 10) % 10
	var dot_r: float = max(1.0, body * 0.1)
	var ring: float = body * (0.36 if kind >= 5 and kind <= 7 else 0.48)
	for i in range(dots):
		var p := c
		if dots > 1:
			var a: float = -PI / 2.0 + i * TAU / float(dots)
			p = c + Vector2(cos(a), sin(a)) * ring
		ci.draw_circle(p, dot_r, col)
	# the thousands: spikes round the outside
	for i in range(spikes):
		var a: float = -PI / 2.0 + i * TAU / float(spikes)
		_spike(ci, c, a, body + line * 0.2, rad, rad * 0.2, col)

static func _spike(ci: CanvasItem, c: Vector2, a: float, from: float, to: float, half_w: float, col: Color):
	var out := Vector2(cos(a), sin(a))
	var side := Vector2(-out.y, out.x)
	ci.draw_colored_polygon(PoolVector2Array([c + out * to, c + out * from + side * half_w, c + out * from - side * half_w]), col)

# prestige 10,000: the note (the logo's tilted rounded square), each stretch of
# its edge in the next colour of the logo, and twelve spikes
static func _draw_last(ci: CanvasItem, c: Vector2, rad: float, line: float):
	var body: float = rad * 0.7
	var half: float = body * 0.78
	var round_r: float = half * 0.42
	var tilt := deg2rad(-27.0)
	var pts := PoolVector2Array()
	var corners := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	for k in range(4):
		var cc: Vector2 = corners[k] * (half - round_r)
		for j in range(7):
			var a: float = -PI / 2.0 + k * PI / 2.0 + j * (PI / 2.0) / 6.0
			pts.append(c + (cc + Vector2(cos(a), sin(a)) * round_r).rotated(tilt))
	var fill := pts
	ci.draw_colored_polygon(fill, Color(1, 1, 1, 0.18))
	var n: int = pts.size()
	for i in range(n):
		var t: float = float(i) / float(n) * RAINBOW.size()
		var a_col: Color = RAINBOW[int(t) % RAINBOW.size()]
		var b_col: Color = RAINBOW[(int(t) + 1) % RAINBOW.size()]
		ci.draw_line(pts[i], pts[(i + 1) % n], a_col.linear_interpolate(b_col, t - floor(t)), line * 1.1, true)
	for i in range(12):
		var a2: float = -PI / 2.0 + i * TAU / 12.0
		_spike(ci, c, a2, body + line * 0.9, rad, rad * 0.11, RAINBOW[i % RAINBOW.size()])
