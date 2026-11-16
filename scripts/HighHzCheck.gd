extends Node

# 120 Hz on an iPhone or iPad (Settings > 120 Hz, Savia.apply_mobile_tuning):
# finds the highest refresh rate the game really gets, and stays on it.
#
# Asking the screen for 120 isn't enough there. The engine draws with OpenGL
# ES, and an iPhone asked for 120 that way settles at 60: its screen timer
# keeps firing 120 times a second, but each frame then waits for the last
# picture to come back from the screen and misses every other refresh. It
# shows 60 frames a second and feels delayed, which is worse than plain 60.
# 80 holds. (iOS itself can also hold the screen at 60: Low Power Mode,
# Accessibility > Motion > Limit Frame Rate, heat, an app installed before
# 120 Hz was supported.)
#
# So a few seconds after the menu is up, each way is tried for a few seconds
# and the frames are counted, best first:
#   120 Hz as the engine shows frames
#   120 Hz with each of the two other ways of handing a frame to the screen
#     (native helper 3: ios/picker/ChromiaPicker.m, only in an installed .ipa)
#   80 Hz
#   60 Hz
# The first that gives its rate is kept, and remembered for this device for a
# week (a day for 60: user://phone_hz.json), so the next starts only check it
# still holds. Turning 120 Hz off and on starts over. Until a way has passed,
# songs run at 80 (never on a 120 that hasn't been seen to work). Low Power
# Mode ends the tries (nothing is remembered: it's looked at again next start).

const FILE := "user://phone_hz.json"
const TRY_FILE := "user://phone_hz_try.txt"
const FIRST_SETTLE_S := 6.0
const SETTLE_S := 3.0
const MEASURE_S := 3.0
const PASS_SHARE := 0.92 # (of the asked rate)
const KEEP_S := 7 * 86400
const KEEP_60_S := 86400
const SAFE := [80, 0] # asked for while nothing has passed yet

var _plan := []
var _i := 0
var _t := 0.0
var _frames := 0
var _state := 0 # 0 settling, 1 measuring
var _applied := false
var _away := false
var _log := ""
var _report := ""

# --- what to ask the phone for (also read by Savia.apply_mobile_tuning) ---
static func st() -> Dictionary:
	if not Engine.has_meta("phone_hz"):
		var s := {"ask": SAFE.duplicate(), "done": false, "note": "", "saved": {}, "trying": false}
		Engine.set_meta("phone_hz", s)
		var saved := _read()
		# a way that was being tried when the game last went down: one strike
		var f := File.new()
		if f.file_exists(TRY_FILE):
			if f.open(TRY_FILE, File.READ) == OK:
				var mode := f.get_as_text().strip_edges()
				f.close()
				var bad: Dictionary = saved.get("bad", {}) if saved.get("bad", {}) is Dictionary else {}
				bad[mode] = int(bad.get(mode, 0)) + 1
				saved["bad"] = bad
				saved.erase("rate")
				_write(saved)
			Directory.new().remove(TRY_FILE)
		s.saved = saved
		if _fresh(saved, false):
			s.ask = [int(saved.rate), int(saved.get("present", 0))]
	return Engine.get_meta("phone_hz")

# [frames a second, way of showing frames] to ask the helper for with 120 Hz on
static func ask() -> Array:
	return st().ask

static func note() -> String:
	return String(st().note)

static func _read() -> Dictionary:
	var f := File.new()
	if not f.file_exists(FILE) or f.open(FILE, File.READ) != OK:
		return {}
	var p = JSON.parse(f.get_as_text())
	f.close()
	return p.result if p.error == OK and p.result is Dictionary else {}

static func _write(d: Dictionary):
	var f := File.new()
	if f.open(FILE, File.WRITE) == OK:
		f.store_string(JSON.print(d))
		f.close()

# (same_helper: only once the helper has answered, so not at the very start)
static func _fresh(saved: Dictionary, same_helper: bool) -> bool:
	if not saved.has("rate") or not (int(saved.rate) in [60, 80, 120]) or String(saved.get("model", "")) != OS.get_model_name():
		return false
	if same_helper and int(saved.get("helper", 0)) != helper_level(String(Rhythia.mobile_tuning_status)):
		return false
	return OS.get_unix_time() - int(saved.get("t", 0)) < (KEEP_60_S if int(saved.rate) <= 60 else KEEP_S)

# 120 Hz was switched by hand: everything is tried again from the top
static func forget():
	var s := st()
	var saved: Dictionary = s.saved
	saved.erase("rate")
	saved.erase("told")
	_write(saved)
	s.ask = SAFE.duplicate()
	s.done = false
	s.note = ""
	Directory.new().remove(TRY_FILE)
	var n = Rhythia.get_node_or_null("HighHzCheck")
	if n != null:
		Rhythia.remove_child(n) # (now: the next check may start this frame)
		n.queue_free()

static func _value(report: String, key: String) -> String:
	for line in report.split("\n"):
		if line.begins_with(key + " "):
			return line.substr(key.length() + 1).strip_edges()
	return ""

# 0: no helper in this app, 1: sets the rate, 2: also says why 60, 3: other ways of showing frames
static func helper_level(report: String) -> int:
	if report == "":
		return 0
	if _value(report, "helper") != "":
		return int(_value(report, "helper"))
	return 2 if _value(report, "lowpower") != "" else 1

static func screen_top() -> float:
	if Engine.has_meta("ios_native_fake"):
		return float(Engine.get_meta("ios_native_fake").screen)
	return OS.get_screen_refresh_rate()

static func wanted() -> bool:
	return (OS.has_feature("iOS") or Engine.has_meta("ios_native_fake")) and Rhythia.dev == "mobile" and bool(Rhythia.mobile_high_hz) \
		and String(Rhythia.mobile_tuning_status) != "" and screen_top() > 61.0 and not bool(st().done)

# --- the tries ---
func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	var s := st()
	var level := helper_level(String(Rhythia.mobile_tuning_status))
	var ladder := [[120, 0]]
	var bad: Dictionary = s.saved.get("bad", {}) if s.saved.get("bad", {}) is Dictionary else {}
	if level >= 3:
		for mode in [1, 2]:
			if int(bad.get(str(mode), 0)) < 2:
				ladder.append([120, mode])
	ladder.append([80, 0])
	ladder.append([60, 0])
	# (a remembered way: only that one and what's under it)
	var from := 0
	if _fresh(s.saved, true):
		for k in ladder.size():
			if ladder[k][0] == int(s.saved.rate) and ladder[k][1] == int(s.saved.get("present", 0)):
				from = k
	_plan = ladder.slice(from, ladder.size() - 1)
	_t = -(FIRST_SETTLE_S - SETTLE_S)

func _calm(delta: float) -> bool:
	var cs = get_tree().current_scene
	return cs != null and (cs.name == "Menu" or cs.name == "VRMenuHolder") and delta <= 0.1 and OS.is_window_focused()

func _set_ask(a: Array, trying: bool):
	var s := st()
	s.ask = [int(a[0]), int(a[1])]
	var d := Directory.new()
	if trying and int(a[1]) > 0:
		var f := File.new()
		if f.open(TRY_FILE, File.WRITE) == OK:
			f.store_string(str(int(a[1])))
			f.close()
	elif d.file_exists(TRY_FILE):
		d.remove(TRY_FILE)
	Rhythia.apply_mobile_tuning()

func _process(delta: float):
	if not wanted():
		if not bool(st().done) and _applied:
			_set_ask(SAFE, false)
		queue_free()
		return
	if not _calm(delta):
		# (only a calm stretch of the menu says anything; a song meanwhile runs on the safe rate)
		if _applied and not _away:
			_away = true
			_set_ask(SAFE, false)
		_applied = false
		_state = 0
		_t = min(_t, 0.0)
		return
	_away = false
	var cur: Array = _plan[_i]
	if not _applied:
		_applied = true
		_state = 0
		_t = min(_t, 0.0)
		_set_ask(cur, true)
		return
	_t += delta
	if _state == 0:
		if _t >= SETTLE_S:
			_state = 1
			_t = 0.0
			_frames = 0
		return
	_frames += 1
	if _t < MEASURE_S:
		return
	var fps: float = float(_frames) / _t
	if Engine.has_meta("ios_native_fake"):
		fps = float(Engine.get_meta("ios_native_fake").fps(cur[0], cur[1]))
	_log += "%s%d%s: %.0f fps" % ["" if _log == "" else ", ", cur[0], "" if cur[1] == 0 else " (way %d)" % cur[1], fps]
	if int(cur[0]) <= 60 or fps >= float(cur[0]) * PASS_SHARE:
		_finish(cur, "ok", fps)
		return
	# is iOS holding the screen at 60? (then nothing higher can pass, whatever the way)
	var report: String = load("res://scripts/IosNative.gd").tune(0, -1.0)
	_report = report
	if _value(report, "lowpower") == "1" or _value(report, "plist120") == "0":
		_log += " [%s]" % report.replace("\n", ", ")
		var s := st()
		var back: Array = [int(s.saved.rate), int(s.saved.get("present", 0))] if _fresh(s.saved, true) else SAFE
		if _value(report, "lowpower") == "1":
			_finish(back, "lowpower", fps)
		else:
			_finish([60, 0], "plist", fps)
		return
	_i += 1
	_applied = false
	_t = 0.0

func _finish(a: Array, how: String, fps: float):
	var s := st()
	s.done = true
	_set_ask(a, false)
	var saved: Dictionary = s.saved
	var level := helper_level(String(Rhythia.mobile_tuning_status))
	var outcome := how if how != "ok" else "%d/%d" % [a[0], a[1]]
	# (kept only when it's known that Low Power Mode wasn't what held it: an
	# older helper can't tell, so there it's found again each start)
	if how == "ok" and (int(a[0]) >= 120 or level >= 2):
		saved["rate"] = int(a[0])
		saved["present"] = int(a[1])
		saved["model"] = OS.get_model_name()
		saved["helper"] = level
		if not saved.has("t") or OS.get_unix_time() - int(saved.get("t", 0)) >= KEEP_S or String(saved.get("told", "")) != outcome:
			saved["t"] = OS.get_unix_time()
	elif how != "lowpower":
		saved.erase("rate")
	var told: String = String(saved.get("told", ""))
	saved["told"] = outcome
	_write(saved)
	var text := ""
	var kind: int = Globals.NOTIFY_WARN
	match how:
		"lowpower":
			s.note = "60 now: Low Power Mode"
			text = "Low Power Mode is on, and with it an iPhone holds its screen at 60 Hz. Turn it off (Settings > Battery) and the game goes up by itself."
		"plist":
			s.note = "60: reinstall needed"
			text = "This installed app can't go above 60 Hz. Install the latest chromia-ios.ipa once (in-app updates can't change that part)."
		_:
			if int(a[0]) >= 120:
				s.note = "" if int(a[1]) == 0 else "on"
				kind = Globals.NOTIFY_SUCCEED
				if told != "" and told != outcome or int(a[1]) > 0 and told != outcome:
					text = "120 Hz is working: the game is drawing %d frames a second." % int(round(fps))
			elif int(a[0]) == 80:
				s.note = "running at 80"
				text = "This device doesn't hold 120 frames a second with the game's engine (asked for 120, it shows 60 and feels delayed), but it holds 80. The game is at 80 Hz now, up from 60."
				if level < 3:
					text += " Installing the latest chromia-ios.ipa once lets the game try two more ways of reaching 120."
				kind = Globals.NOTIFY_INFO
			else:
				s.note = "60: nothing higher held"
				text = "Neither 120 nor 80 Hz held on this device, so the game stays at 60."
				# (the screen timer itself at 60: that's iOS, not the game)
				var link := _value(_report, "link")
				if link != "" and float(link.split(" ")[0]) > 1.0 and float(link.split(" ")[0]) < 70.0:
					text += " iOS is only giving the game 60 Hz: check Settings > Accessibility > Motion > Limit Frame Rate, and that the device isn't hot."
				elif level < 2:
					text += " The usual causes: Low Power Mode, Settings > Accessibility > Motion > Limit Frame Rate, or an app installed before 120 Hz was supported (install the latest chromia-ios.ipa once)."
	Rhythia.trail("phone refresh rate: %s -> %s (helper %d, %s, screen %.0f)" % [_log, outcome, level, OS.get_model_name(), screen_top()])
	if text != "" and told != outcome:
		Globals.notify(kind, text, "120 Hz", 12)
	queue_free()
