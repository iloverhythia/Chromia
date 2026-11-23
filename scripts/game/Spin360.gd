extends Reference

# 360 Shuffle: the 360 mod, but the spin keeps changing speed and direction.
# It isn't random: the changes come from the map's id (its seed), so a map
# always spins the same way, for everyone and in its replays. The 360 speed
# slider sets how fast (the changes go from about a third of it to one and a
# half times it; a minus speed turns them all the other way).
#
# Every 1.5 to 5 seconds of map time a new speed and direction, eased into
# over 0.7 seconds, so the notes never jump. Before the map's time 0 it spins
# like the plain 360 mod.
#
# The website's replay viewer draws the same spin (savia_web
# website/assets/chromia-formats.js spin360): the same number generator
# (mulberry32, seeded with FNV-1a of the id's UTF-8 bytes), the same steps.
# Change one, change both.

const SEG_MIN := 1500.0
const SEG_MAX := 5000.0
const EASE := 700.0
const HORIZON := 3600000.0 # (an hour of map time)
const RATE := 0.0006 # radians per ms at speed 1 (NoteManager's plain 360)
const M32 := 0xFFFFFFFF

var key := ""
var _rate0 := 0.0
var _t := [] # where each part starts (map ms)
var _a := [] # the angle there
var _p := [] # the speed before it (eased from)
var _r := [] # its speed
var _e := [] # how long the easing takes
var _s := 0 # the generator's state

static func _imul(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & M32

func _rand() -> float:
	_s = (_s + 0x6D2B79F5) & M32
	var t := _imul(_s ^ (_s >> 15), _s | 1)
	t = t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & M32)
	return float((t ^ (t >> 14)) & M32) / 4294967296.0

static func seed_of(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8():
		h = _imul(h ^ int(b), 16777619)
	return h

func _init(seed_text: String, speed: float):
	key = "%s|%s" % [seed_text, speed]
	_s = seed_of(seed_text)
	var sgn := -1.0 if speed < 0 else 1.0
	var base := abs(speed) * RATE
	_rate0 = speed * RATE
	var t := 0.0
	var a := 0.0
	var prev := _rate0
	while t < HORIZON:
		var length := SEG_MIN + _rand() * (SEG_MAX - SEG_MIN)
		var dir := 1.0 if _rand() < 0.5 else -1.0
		var mag := 0.35 + _rand() * 1.15
		var rate := sgn * dir * mag * base
		var e: float = min(EASE, length)
		_t.append(t); _a.append(a); _p.append(prev); _r.append(rate); _e.append(e)
		a = _at(_t.size() - 1, length)
		t += length
		prev = rate

func _at(i: int, dt: float) -> float:
	var p: float = _p[i]
	var r: float = _r[i]
	var e: float = _e[i]
	if dt < e:
		var x := dt / e
		return _a[i] + p * dt + (r - p) * e * (x * x * x - x * x * x * x / 2.0)
	return _a[i] + p * e + (r - p) * e * 0.5 + r * (dt - e)

# the notes' turn (radians) at this map time
func angle(ms: float) -> float:
	if ms <= 0.0 or _t.empty():
		return ms * _rate0
	var i := _t.bsearch(ms, true) - 1
	if i < 0: i = 0
	return _at(i, ms - _t[i])
