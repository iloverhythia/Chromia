extends DanceMover

# "Realistic autoplay" (Experimental settings): moves the cursor like a person
# playing the map instead of the perfect bouncy curves. It still hits every
# note, but each move has a reaction delay, a curved, slightly uneven path that
# speeds up then slows down (and overshoots a bit on fast jumps), aims a little
# off the note's center, has a tiny hand tremor and drifts back toward the
# middle during breaks.
#
# Positions are in grid units (0..2 on both axes), like BouncyDanceMover.

const CENTER := Vector2(1, 1)
const AIM_RADIUS := 0.2       # how far from a note's center it aims (hitbox half-size is ~0.57)
const TREMOR := 0.006         # hand shake, grid units
const BREAK_MS := 1100.0      # longer gaps (real time) count as a break

# per note: x, y = aim point, z = time
var notes: PoolVector3Array = PoolVector3Array()
# per move into note i: curve bend, overshoot, reaction delay (real ms), early arrival (real ms)
var bend: PoolRealArray = PoolRealArray()
var overshoot: PoolRealArray = PoolRealArray()
var react: PoolRealArray = PoolRealArray()
var early: PoolRealArray = PoolRealArray()
var idx: int = 0
var speed: float = 1.0

func _init(song: Song):
	speed = max(Globals.speed_multi[Rhythia.mod_speed_level], 0.05)
	var raw := []
	for n in song.read_notes():
		var x: float = float(n[0])
		var y: float = float(n[1])
		if Rhythia.mod_mirror_x: x = 2 - x
		if Rhythia.mod_mirror_y: y = 2 - y
		var z: float = float(n[2])
		if raw.size() > 0 and z - raw[raw.size() - 1].z < 10:
			# notes at (almost) the same time: aim between them
			var last: Vector3 = raw[raw.size() - 1]
			raw[raw.size() - 1] = Vector3((last.x + x) / 2.0, (last.y + y) / 2.0, last.z)
		else:
			raw.append(Vector3(x, y, z))

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(song.id))
	var prev_aim := CENTER
	for i in range(raw.size()):
		var p: Vector3 = raw[i]
		var pos := Vector2(p.x, p.y)
		# aim: random point near the center, biased slightly toward where the cursor comes from
		var ang := rng.randf() * TAU
		var rad := AIM_RADIUS * sqrt(rng.randf()) * 0.8
		var off := Vector2(cos(ang), sin(ang)) * rad
		if i > 0:
			var from_dir: Vector2 = (prev_aim - pos)
			if from_dir.length() > 0.001:
				off += from_dir.normalized() * AIM_RADIUS * 0.25
		if off.length() > AIM_RADIUS:
			off = off.normalized() * AIM_RADIUS
		var aim := pos + off
		notes.append(Vector3(aim.x, aim.y, p.z))

		var gap_real: float = 1000.0
		if i > 0:
			gap_real = (p.z - raw[i - 1].z) / speed
		var dist: float = prev_aim.distance_to(aim)
		bend.append(rng.randf_range(-0.16, 0.16))
		# fast, long jumps overshoot a little; slow ones don't
		var urgency: float = clamp(dist / max(gap_real, 1.0) * 250.0, 0.0, 1.0)
		overshoot.append(urgency * rng.randf_range(0.02, 0.09))
		react.append(min(gap_real * rng.randf_range(0.08, 0.2), rng.randf_range(35.0, 90.0)))
		early.append(min(gap_real * rng.randf_range(0.05, 0.15), rng.randf_range(10.0, 35.0)))
		prev_aim = aim

# minimum-jerk profile (how hands move between targets), with optional overshoot
static func _ease(t: float, ov: float) -> float:
	t = clamp(t, 0.0, 1.0)
	var s := t * t * t * (10.0 + t * (-15.0 + 6.0 * t))
	if ov > 0.0:
		s += ov * sin(PI * s) * s
	return s

func _tremor(ms: float) -> Vector2:
	var t := ms / speed * 0.001
	return Vector2(
		sin(t * 9.3) + 0.6 * sin(t * 23.1 + 1.7),
		sin(t * 11.7 + 0.5) + 0.6 * sin(t * 19.9 + 2.9)
	) * TREMOR

func _update(ms: float) -> Vector2:
	var count := notes.size()
	if count == 0:
		return CENTER
	# find the next note (ms only moves forward, except when seeking)
	if idx > 0 and idx < count and ms < notes[idx - 1].z:
		idx = 0
	while idx < count and notes[idx].z <= ms:
		idx += 1

	if idx >= count:
		# after the last note: ease back toward the middle
		var last: Vector3 = notes[count - 1]
		var lp := Vector2(last.x, last.y)
		var k: float = _ease((ms - last.z) / speed / 900.0, 0.0)
		return lp.linear_interpolate(lp.linear_interpolate(CENTER, 0.6), k) + _tremor(ms)

	var to: Vector3 = notes[idx]
	var to_p := Vector2(to.x, to.y)
	var from_p: Vector2
	var from_t: float
	if idx == 0:
		from_p = CENTER
		from_t = to.z - 600.0 * speed
	else:
		var f: Vector3 = notes[idx - 1]
		from_p = Vector2(f.x, f.y)
		from_t = f.z

	var gap_real: float = (to.z - from_t) / speed
	var start_real: float = react[idx]
	var end_real: float = gap_real - early[idx]
	if gap_real > BREAK_MS and idx > 0:
		# break: relax toward the middle, then move to the next note in time
		var move_len: float = clamp(250.0 + from_p.distance_to(to_p) * 160.0, 250.0, 600.0)
		var now_real: float = (ms - from_t) / speed
		var rest_p: Vector2 = from_p.linear_interpolate(CENTER, 0.45)
		if now_real < gap_real - move_len:
			var k: float = _ease(now_real / max(gap_real - move_len, 1.0) * 1.6, 0.0)
			return from_p.linear_interpolate(rest_p, k) + _tremor(ms)
		from_p = rest_p
		start_real = gap_real - move_len
	if end_real <= start_real:
		start_real = 0.0
		end_real = max(gap_real * 0.9, 1.0)

	var now: float = (ms - from_t) / speed
	var t: float = (now - start_real) / max(end_real - start_real, 1.0)
	var s: float = _ease(t, overshoot[idx])
	var p: Vector2 = from_p.linear_interpolate(to_p, s)
	# curve: bend sideways, most in the middle of the move
	var d: Vector2 = to_p - from_p
	if d.length() > 0.001:
		var perp := Vector2(-d.y, d.x)
		p += perp * bend[idx] * sin(PI * clamp(s, 0.0, 1.0))
	p += _tremor(ms) * (0.4 + 0.6 * sin(PI * clamp(t, 0.0, 1.0)))
	return Vector2(clamp(p.x, -0.5, 2.5), clamp(p.y, -0.5, 2.5))
