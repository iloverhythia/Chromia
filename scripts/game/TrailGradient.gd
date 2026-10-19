extends Reference

# Helpers for the cursor trail gradient (Rhythia.trail_gradient = [[offset, "rrggbbaa"], ...]).
# The trail never samples the gradient per frame through Gradient calls: it builds a
# small colour lookup table once and indexes into it.

const LUT_SIZE = 64
const DEFAULT_POINTS = [[0.0, "ffffffff"], [1.0, "ffc3a6cc"]] # Godot html = aarrggbb

# Returns a clean, sorted list of [float offset, Color] with endpoints at 0 and 1.
static func parse_points(raw) -> Array:
	var pts: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for p in raw:
			if typeof(p) != TYPE_ARRAY or p.size() < 2:
				continue
			var off = clamp(float(p[0]), 0.0, 1.0)
			var c: Color = Color(1, 1, 1)
			if typeof(p[1]) == TYPE_COLOR:
				c = p[1]
			elif typeof(p[1]) == TYPE_STRING and String(p[1]).is_valid_html_color():
				c = Color(String(p[1]))
			pts.append([off, c])
	if pts.size() < 2:
		pts = []
		for p in DEFAULT_POINTS:
			pts.append([float(p[0]), Color(p[1])])
	pts.sort_custom(PointSorter, "less")
	# endpoints are pinned to 0 and 1
	pts[0][0] = 0.0
	pts[pts.size() - 1][0] = 1.0
	return pts

static func serialize(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append([stepify(float(p[0]), 0.0001), (p[1] as Color).to_html(true)])
	return out

static func sample(pts: Array, x: float) -> Color:
	if pts.empty():
		return Color(1, 1, 1)
	if x <= pts[0][0]:
		return pts[0][1]
	for i in range(1, pts.size()):
		var b = pts[i]
		if x <= b[0]:
			var a = pts[i - 1]
			var span: float = b[0] - a[0]
			if span <= 0.00001:
				return b[1]
			return (a[1] as Color).linear_interpolate(b[1], (x - a[0]) / span)
	return pts[pts.size() - 1][1]

static func build_lut(raw, size: int = LUT_SIZE) -> PoolColorArray:
	var pts = parse_points(raw)
	var lut := PoolColorArray()
	lut.resize(size)
	for i in size:
		lut[i] = sample(pts, float(i) / float(size - 1))
	return lut

class PointSorter:
	static func less(a, b) -> bool:
		return a[0] < b[0]
