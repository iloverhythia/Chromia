extends Reference

# New Absolute Mode on a touch screen (Settings > New Absolute Mode; Cursor.gd):
# the cursor is the finger's newest sample, with nothing smoothed. The lead
# that makes up for the screen's delay (Settings > Prediction) is the newest
# step's speed x the lead time, there in full the moment a sample comes and
# gone in full once the finger has stopped. No easing in or out, no gliding
# between samples: the cursor moves when the finger's samples say so.
#
# (TouchPredictor.gd is the smooth one: it evens the samples out over drawn
# frames and eases the lead. Same two calls, add and offset.)

const NEW_STROKE_USEC := 120000 # without a sample this long: a new movement
const QUIET := 2.5 # touch intervals without a sample: the finger has stopped
const RATES := [60.0, 90.0, 120.0, 144.0, 240.0] # what screens deliver

var vel := Vector2.ZERO # px/s, from the newest step alone
var interval := 1.0 / 60.0 # s between touch samples, as measured
var _p := Vector2.ZERO
var _has := false
var _last := 0 # usec: when the newest sample arrived
var _arr := []

func reset():
	_has = false
	vel = Vector2.ZERO
	_arr.clear()

func add(p: Vector2, now_usec: int):
	if _has and now_usec - _last > NEW_STROKE_USEC:
		reset()
	# how often the screen gives samples (they arrive a frame's worth at once,
	# so counted over the last ones, and set on the nearest real rate)
	_arr.append(now_usec)
	if _arr.size() > 32:
		_arr.pop_front()
	var na := _arr.size()
	if na >= 8:
		var obs := float(_arr[na - 1] - _arr[0]) / 1000000.0 / float(na - 1)
		if obs >= 0.003 and obs <= 0.05:
			for r in RATES:
				if abs(obs * r - 1.0) < 0.08:
					obs = 1.0 / r
					break
			interval += (obs - interval) * 0.1
	if _has:
		# (samples are an interval apart whatever moment they were handled at;
		# after a gap, as many intervals as went by)
		var steps: float = max(1.0, round(float(now_usec - _last) / 1000000.0 / interval))
		vel = (p - _p) / (steps * interval)
	_p = p
	_has = true
	_last = now_usec

# How far from the newest sample the cursor is drawn at now_usec.
# lead_cap: the most the lead may be, in the same units as the samples.
func offset(now_usec: int, lead_s: float, lead_cap: float, _frame: bool = false) -> Vector2:
	if not _has or lead_s <= 0.0:
		return Vector2.ZERO
	if float(now_usec - _last) / 1000000.0 > QUIET * interval:
		return Vector2.ZERO # (stopped: on the finger at once)
	var o := vel * lead_s
	if lead_cap > 0.0 and o.length() > lead_cap:
		o = o.normalized() * lead_cap
	return o
