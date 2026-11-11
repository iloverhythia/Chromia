extends Reference

# The phone cursor's prediction as it was before TouchPredictor.gd (Settings >
# Old Cursor Movement): the speed from when each touch was handled, smoothed;
# the cursor led by that speed for the time since the last touch plus the
# chosen lead, no further than the cap; back on the touch itself as soon as a
# frame comes more than one and a half frames after the last touch. Kept as it
# was, for players who prefer how it felt. Same calls as TouchPredictor.gd.

var vel := Vector2.ZERO # px/s, smoothed
var _last := Vector2.ZERO
var _t := 0

func reset():
	vel = Vector2.ZERO
	_t = 0

func add(p: Vector2, now_usec: int):
	var dt := float(now_usec - _t) / 1000000.0
	if _t > 0 and dt > 0.0005 and dt < 0.1:
		var v := (p - _last) / dt
		vel = vel.linear_interpolate(v, 0.6)
	else:
		vel = Vector2.ZERO
	_last = p
	_t = now_usec

func offset(now_usec: int, lead_s: float, lead_cap: float) -> Vector2:
	var fr: float = 1.0 / max(Engine.get_frames_per_second(), 30.0)
	var age: float = (float(now_usec - _t) / 1000000.0) if _t > 0 else 1.0
	if age > 1.5 * fr:
		return Vector2.ZERO
	var ahead := vel * (age + lead_s)
	if lead_cap > 0.0 and ahead.length() > lead_cap:
		ahead = ahead.normalized() * lead_cap
	return ahead
