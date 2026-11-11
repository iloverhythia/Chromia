extends Reference

# Where a finger is "now", from the touch samples that have arrived (phones,
# Settings > No Touch Delay). A touch sample is already old when it's handled,
# and samples don't line up with drawn frames: some frames get none, some get
# two. Drawn as they come, the cursor trails the finger and moves in uneven
# steps. This keeps the last few samples and gives, for any moment, how far
# past the last sample the finger has got:
#   glide: speed x the time since the last sample was taken (fills frames that
#          got no sample, so the cursor moves every frame, by the same amount);
#   lead:  speed x the chosen prediction time (makes up for the screen's delay).
# When samples stop (the finger rests or lifts), both ease out to nothing over
# a couple of touch intervals, so the cursor settles on the real spot without
# a jump back.
#
# When a sample is *handled* says little about when it was *taken*: the screen
# takes them at a steady rate, the game gets them in a frame's worth at once.
# So the samples' own clock is rebuilt: each one is a touch interval after the
# one before (the interval is measured from how many arrive over time), never
# later than it arrived, and pulled gently towards arrival so it can't wander.
# Speeds measured on that clock don't jump when a frame brings no sample or two.

const KEEP_USEC := 90000.0 # samples older than this are dropped
const NEW_STROKE_USEC := 120000 # without a sample this long: a new movement
const RATES := [60.0, 90.0, 120.0, 144.0, 240.0] # what screens deliver

var span_usec := 24000.0 # the longer stretch the speed is measured over
var w_step := 0.5 # how much of the speed is the newest step's
var vel := Vector2.ZERO # px/s
var interval := 1.0 / 60.0 # s between touch samples, as measured
var _t := [] # usec (float): when each sample was taken, on the rebuilt clock
var _p := [] # Vector2
var _arr := [] # usec (int): when the last samples of this movement arrived
var _arr_last := 0

func reset():
	_t.clear()
	_p.clear()
	_arr.clear()
	vel = Vector2.ZERO

func add(p: Vector2, now_usec: int):
	if not _t.empty() and now_usec - _arr_last > NEW_STROKE_USEC:
		reset()
	_arr.append(now_usec)
	if _arr.size() > 32:
		_arr.pop_front()
	var tau := float(now_usec)
	if not _t.empty():
		var na := _arr.size()
		if na >= 8:
			var obs := float(_arr[na - 1] - _arr[0]) / 1000000.0 / float(na - 1)
			if obs >= 0.003 and obs <= 0.05:
				for r in RATES:
					if abs(obs * r - 1.0) < 0.08:
						obs = 1.0 / r
						break
				interval += (obs - interval) * 0.1
		var iv_usec := interval * 1000000.0
		var last_tau: float = _t[_t.size() - 1]
		tau = min(float(now_usec), last_tau + iv_usec)
		tau += (float(now_usec) - tau) * 0.02
		tau = max(tau, float(now_usec) - 1.5 * iv_usec)
		tau = max(tau, last_tau + 0.5 * iv_usec)
	_arr_last = now_usec
	_t.append(tau)
	_p.append(p)
	while _t.size() > 2 and tau - _t[0] > KEEP_USEC:
		_t.pop_front()
		_p.pop_front()
	_measure()

func _measure():
	var n := _t.size()
	if n < 2:
		vel = Vector2.ZERO
		return
	var last_t: float = _t[n - 1]
	var last_p: Vector2 = _p[n - 1]
	var step_dt: float = (last_t - _t[n - 2]) / 1000000.0
	var k := n - 2
	while k > 0 and last_t - _t[k] < span_usec:
		k -= 1
	var span_dt: float = (last_t - _t[k]) / 1000000.0
	if span_dt < 0.0005:
		vel = Vector2.ZERO
		return
	var v_span: Vector2 = (last_p - _p[k]) / span_dt
	if k == n - 2 or step_dt < 0.0005:
		vel = v_span
	else:
		vel = ((last_p - _p[n - 2]) / step_dt) * w_step + v_span * (1.0 - w_step)

# How far past the last sample the finger is at now_usec, plus the lead.
# lead_cap: the most the lead may be, in the same units as the samples.
func offset(now_usec: int, lead_s: float, lead_cap: float) -> Vector2:
	var n := _t.size()
	if n < 2:
		return Vector2.ZERO
	# (easing out goes by when the last one arrived: late samples are still samples)
	var quiet := float(now_usec - _arr_last) / 1000000.0
	var hold := 1.25 * interval
	var gone := 2.75 * interval
	if quiet >= gone:
		return Vector2.ZERO
	var fade := 1.0
	if quiet > hold:
		var x := (quiet - hold) / (gone - hold)
		fade = 1.0 - x * x * (3.0 - 2.0 * x)
	var age: float = clamp((float(now_usec) - _t[n - 1]) / 1000000.0, 0.0, 2.0 * interval)
	var glide: Vector2 = vel * age
	var ahead: Vector2 = vel * lead_s
	if lead_cap > 0.0 and ahead.length() > lead_cap:
		ahead = ahead.normalized() * lead_cap
	return (glide + ahead) * fade
