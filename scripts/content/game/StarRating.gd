extends Reference

# Star rating (SR): a line-by-line port of SSQE+'s offline star rating
# (Web Editor/js/starrating.js in iloverhythia/Sound-Space-Quantum-Editor-Plus),
# which is Rhythia's StarRating: osu! standard aim strain at circle size 2 with
# Relax, the grid scaled to 50 px a cell, and a note closer than 1.25 cells to
# the note kept before it left out.

const SCALE := 0.71
const RADIUS := 64.0 * SCALE
const NORM := 50.0
const MIN_DT := 25.0
const SECTION := 400.0
const DECAY_W := 0.9
const AIM_MULT := 23.55
const AIM_DECAY := 0.15
const WIDE_M := 1.5
const ACUTE_M := 1.95
const VC_M := 0.75
const DIFF_M := 0.0675
const PERF_M := 1.14
const MERGE := 1.25

class _ByTime:
	# by time, then by original order (like the JS stable sort)
	func cmp(a, b) -> bool:
		if a[2] != b[2]:
			return a[2] < b[2]
		return a[3] < b[3]

static func _wide(a: float) -> float:
	return pow(sin(0.75 * (clamp(a, PI / 6.0, 5.0 / 6.0 * PI) - PI / 6.0)), 2)

# Notes the game counts: one closer than 1.25 cells to the one kept before it
# is part of it. (As in SSQE+, the last note is never added.)
static func _site_filter(ns: Array) -> Array:
	ns = ns.duplicate()
	var out := []
	var i := 0
	while i < ns.size() - 1:
		var a = ns[i]
		var b = ns[i + 1]
		if Vector2(b[0] - a[0], b[1] - a[1]).length() < MERGE:
			ns.remove(i + 1)
			continue
		out.append(a)
		i += 1
	return out

static func _aim_value(d: int, st: Array, jump: Array, ang: Array) -> float:
	if d <= 1:
		return 0.0
	var cv: float = jump[d] / st[d]
	var pv: float = jump[d - 1] / st[d - 1]
	var wide := 0.0
	var acute := 0.0
	var vc := 0.0
	if max(st[d], st[d - 1]) < 1.25 * min(st[d], st[d - 1]) and ang[d] >= 0 and ang[d - 1] >= 0 and ang[d - 2] >= 0:
		var ab: float = min(cv, pv)
		wide = _wide(ang[d])
		acute = 1.0 - wide
		if st[d] > 100:
			acute = 0.0
		else:
			acute *= 1.0 - _wide(ang[d - 1])
			acute *= min(ab, 125.0 / st[d])
			acute *= pow(sin(PI / 2.0 * min(1.0, (100.0 - st[d]) / 25.0)), 2)
			acute *= pow(sin(PI / 2.0 * (clamp(jump[d], 50.0, 100.0) - 50.0) / 50.0), 2)
		wide *= ab * (1.0 - min(wide, pow(_wide(ang[d - 1]), 3)))
		acute *= 0.5 + 0.5 * (1.0 - min(acute, pow(1.0 - _wide(ang[d - 2]), 3)))
	if max(pv, cv) != 0.0:
		var dr := pow(sin(PI / 2.0 * abs(pv - cv) / max(pv, cv)), 2)
		var ob: float = min(125.0 / min(st[d], st[d - 1]), abs(pv - cv))
		vc = ob * dr * pow(min(st[d], st[d - 1]) / max(st[d], st[d - 1]), 2)
	return cv + max(acute * ACUTE_M, wide * WIDE_M + vc * VC_M)

# notes: Array of [x, y, ms] in grid cells -> the star rating (0 for fewer than two notes)
static func calculate(notes_in: Array) -> float:
	var sorter := _ByTime.new()
	var notes := []
	for i in range(notes_in.size()):
		var n = notes_in[i]
		notes.append([float(n[0]), float(n[1]), float(n[2]), i])
	notes.sort_custom(sorter, "cmp")
	# (the game's beatmap template starts with one circle of its own)
	var objs := [[256.0, 192.0, 24202.0, 0]]
	for n in _site_filter(notes):
		objs.append([floor(n[0] * 50.0 + 0.5), floor(n[1] * 50.0 + 0.5), n[2], objs.size()])
	objs.sort_custom(sorter, "cmp")
	if objs.size() < 3:
		return 0.0
	var sf := NORM / RADIUS
	var count := objs.size() - 1
	var delta := []
	var start := []
	var st := []
	var jump := []
	var ang := []
	for i in range(1, objs.size()):
		var a = objs[i - 1]
		var b = objs[i]
		delta.append(b[2] - a[2])
		start.append(b[2])
		st.append(max(b[2] - a[2], MIN_DT))
		jump.append(Vector2((b[0] - a[0]) * sf, (b[1] - a[1]) * sf).length())
		var an := -1.0
		if i > 1:
			var c = objs[i - 2]
			var v1 := Vector2(c[0] - a[0], c[1] - a[1])
			var v2 := Vector2(b[0] - a[0], b[1] - a[1])
			an = abs(atan2(v1.x * v2.y - v1.y * v2.x, v1.x * v2.x + v1.y * v2.y))
		ang.append(an)
	var peaks := []
	var peak := 0.0
	var end: float = ceil(start[0] / SECTION) * SECTION
	var strain := 0.0
	for d in range(count):
		while start[d] > end:
			peaks.append(peak)
			var ps: float = start[d - 1] if d > 0 else 0.0
			peak = strain * pow(AIM_DECAY, (end - ps) / 1000.0)
			end += SECTION
		strain *= pow(AIM_DECAY, delta[d] / 1000.0)
		strain += _aim_value(d, st, jump, ang) * AIM_MULT
		peak = max(strain, peak)
	peaks.append(peak)
	var strains := []
	for p in peaks:
		if p > 0:
			strains.append(p)
	strains.sort()
	strains.invert()
	for i in range(min(strains.size(), 10)):
		strains[i] *= 0.75 + 0.25 * log(1.0 + 9.0 * clamp(i / 10.0, 0.0, 1.0)) / log(10.0)
	strains.sort()
	strains.invert()
	var diff := 0.0
	var w := 1.0
	for s in strains:
		diff += s * w
		w *= DECAY_W
	diff *= 1.06
	var aim := sqrt(diff) * DIFF_M * 0.9
	var base_aim := pow(5.0 * max(1.0, aim / 0.0675) - 4.0, 3) / 100000.0
	var base_perf := pow(pow(base_aim, 1.1) + pow(1.0 / 100000.0, 1.1), 1.0 / 1.1)
	if base_perf <= 0.00001:
		return 0.0
	return pow(PERF_M, 1.0 / 3.0) * 0.027 * (pow(100000.0 / pow(2.0, 1.0 / 1.1) * base_perf, 1.0 / 3.0) + 4.0)
