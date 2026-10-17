extends Reference

const Sorter = preload("res://scripts/content/game/StarRatingSorter.gd")

# Star rating: Rhythia's formula, which is osu!'s aim-strain difficulty with
# Rhythia-specific settings. Only cursor movement (aim) is measured.
# Constants not given in Rhythia's description use osu!'s values (marked).

const MIN_NOTE_DISTANCE := 1.25          # cells; closer notes merge into the last one
const PIXELS_PER_CELL := 50.0
const JUMP_SCALE := 50.0 / 45.44         # 1 cell ~ 55 units
const TEMPLATE_CIRCLE := [256.0, 192.0, 24202.0]  # px, px, ms (from the game's map template)
const MIN_STRAIN_TIME := 25.0
const SECTION_LENGTH := 400.0
const REDUCED_SECTIONS := 10
const REDUCED_BASELINE := 0.75
const DECAY_WEIGHT := 0.9
const DIFFICULTY_MULTIPLIER := 1.06
# osu! values
const WIDE_ANGLE_MULTIPLIER := 1.5
const ACUTE_ANGLE_MULTIPLIER := 1.95
const VELOCITY_CHANGE_MULTIPLIER := 0.75
const SKILL_MULTIPLIER := 23.55
const STRAIN_DECAY_BASE := 0.15
const STAR_MULTIPLIER := 0.0675

static func _wide(angle: float) -> float:
	return pow(sin(0.75 * (clamp(angle, PI / 6.0, 5.0 * PI / 6.0) - PI / 6.0)), 2)

static func _acute(angle: float) -> float:
	return 1.0 - _wide(angle)

# notes: Array of [x, y, ms] in grid cells.
static func calculate(notes: Array) -> float:
	# 1. Notes that count
	var sorted := notes.duplicate()
	sorted.sort_custom(Sorter.new(), "by_time")
	var pts := []  # [px, py, ms]
	var last = null
	for n in sorted:
		if last != null and Vector2(n[0], n[1]).distance_to(Vector2(last[0], last[1])) < MIN_NOTE_DISTANCE:
			continue
		last = n
		pts.append([round(float(n[0]) * PIXELS_PER_CELL), round(float(n[1]) * PIXELS_PER_CELL), float(n[2])])
	if pts.size() < 2:
		return 0.0
	pts.append(TEMPLATE_CIRCLE.duplicate())
	pts.sort_custom(Sorter.new(), "by_time")

	# 2. Per-move values (index i = move from note i-1 to note i)
	var n_pts := pts.size()
	var st := []
	var jump := []
	var vel := []
	var angle := []
	for i in range(n_pts):
		if i == 0:
			st.append(MIN_STRAIN_TIME); jump.append(0.0); vel.append(0.0); angle.append(null)
			continue
		var p := Vector2(pts[i][0], pts[i][1])
		var q := Vector2(pts[i - 1][0], pts[i - 1][1])
		var s: float = max(pts[i][2] - pts[i - 1][2], MIN_STRAIN_TIME)
		var j: float = p.distance_to(q) * JUMP_SCALE
		st.append(s); jump.append(j); vel.append(j / s)
		if i >= 2:
			var r := Vector2(pts[i - 2][0], pts[i - 2][1])
			var v1 := r - q
			var v2 := p - q
			angle.append(abs(atan2(v1.cross(v2), v1.dot(v2))))
		else:
			angle.append(null)

	# 3-4. Aim value per move, strain with decay, 400 ms section peaks
	var peaks := []
	var strain := 0.0
	var section_end: float = ceil(pts[0][2] / SECTION_LENGTH) * SECTION_LENGTH
	var section_peak := 0.0
	var prev_time: float = pts[0][2]
	for i in range(1, n_pts):
		var t: float = pts[i][2]
		while t > section_end:
			peaks.append(section_peak)
			# strain carried into the new section, decayed to its start
			section_peak = strain * pow(STRAIN_DECAY_BASE, (section_end - prev_time) / 1000.0)
			section_end += SECTION_LENGTH
		strain *= pow(STRAIN_DECAY_BASE, (t - prev_time) / 1000.0)
		strain += _aim_value(i, st, jump, vel, angle) * SKILL_MULTIPLIER
		section_peak = max(section_peak, strain)
		prev_time = t
	peaks.append(section_peak)

	# 5. Difficulty
	peaks.sort()
	peaks.invert()
	for i in range(min(REDUCED_SECTIONS, peaks.size())):
		var scale := log(1.0 + 9.0 * clamp(float(i) / REDUCED_SECTIONS, 0.0, 1.0)) / log(10.0)
		peaks[i] *= lerp(REDUCED_BASELINE, 1.0, scale)
	peaks.sort()
	peaks.invert()
	var difficulty := 0.0
	var weight := 1.0
	for p in peaks:
		difficulty += p * weight
		weight *= DECAY_WEIGHT
	difficulty *= DIFFICULTY_MULTIPLIER

	# 6. Stars (osu! performance-to-stars conversion, aim only)
	var aim_rating := sqrt(difficulty) * STAR_MULTIPLIER
	var perf := pow(5.0 * max(1.0, aim_rating / 0.0675) - 4.0, 3) / 100000.0
	if perf <= 0.00001:
		return 0.0
	return pow(1.14, 1.0 / 3.0) * 0.027 * (pow(100000.0 / pow(2.0, 1.0 / 1.1) * perf, 1.0 / 3.0) + 4.0)

static func _aim_value(i: int, st: Array, jump: Array, vel: Array, angle: Array) -> float:
	var v: float = vel[i]
	if i < 2:
		return v
	var v_prev: float = vel[i - 1]
	var wide := 0.0
	var acute := 0.0
	var change := 0.0
	var st_i: float = st[i]
	var st_prev: float = st[i - 1]
	# Angle bonuses only when this gap and the last one are within 1.25x of each other.
	if angle[i] != null and angle[i - 1] != null and max(st_i, st_prev) < 1.25 * min(st_i, st_prev):
		var angle_bonus: float = min(v, v_prev)
		wide = _wide(angle[i])
		acute = _acute(angle[i])
		if st_i > 100.0:
			acute = 0.0
		else:
			acute *= _acute(angle[i - 1]) * min(angle_bonus, 125.0 / st_i) \
				* pow(sin(PI / 2.0 * min(1.0, (100.0 - st_i) / 25.0)), 2) \
				* pow(sin(PI / 2.0 * (clamp(jump[i], 50.0, 100.0) - 50.0) / 50.0), 2)
		wide *= angle_bonus * (1.0 - min(wide, pow(_wide(angle[i - 1]), 3)))
		var last_last_acute := 1.0
		if i >= 3 and angle[i - 2] != null:
			last_last_acute = _acute(angle[i - 2])
		acute *= 0.5 + 0.5 * (1.0 - min(acute, pow(last_last_acute, 3)))
	# Speed-change bonus
	if max(v, v_prev) != 0.0:
		var dv: float = abs(v - v_prev)
		change = min(125.0 / min(st_i, st_prev), dv) * pow(sin(PI / 2.0 * dv / max(v, v_prev)), 2) \
			* pow(min(st_i, st_prev) / max(st_i, st_prev), 2)
	return v + max(acute * ACUTE_ANGLE_MULTIPLIER, wide * WIDE_ANGLE_MULTIPLIER + change * VELOCITY_CHANGE_MULTIPLIER)
