extends Node

# 120 Hz on an iPhone (Settings > 120 Hz, Savia.apply_mobile_tuning) that
# still only shows 60 frames a second. The game can ask for 120, but iOS
# decides: Low Power Mode and Accessibility > Motion > Limit Frame Rate hold
# the screen at 60, an app installed before the 120 Hz support can't go higher,
# and a phone that can't finish a frame in 8 ms shows every other one. Asking
# for 120 and getting 60 is the worst of both (frames land between the
# screen's refreshes: it feels delayed), so: a few seconds after the menu is
# up, the frame rate is measured. If it's pinned near 60, the game goes back
# to plain 60 Hz for this run and says why, as far as the native helper can
# tell (ios/picker/ChromiaPicker.m reports Low Power Mode, the Info.plist key
# and the rate iOS is really giving). Turning 120 Hz off and on, or starting
# the game again, tries once more.

const SETTLE_S := 6.0
const MEASURE_S := 4.0
const ENOUGH_FPS := 75.0 # (above what a 60 Hz screen can give: 120 is getting through)

var _t := 0.0
var _frames := 0
var _state := 0
var _proc_sum := 0.0
var _proc_n := 0

static func wanted() -> bool:
	return (OS.has_feature("iOS") or Engine.has_meta("high_hz_check_anywhere")) and Rhythia.dev == "mobile" and bool(Rhythia.mobile_high_hz) and not Rhythia.has_meta("high_hz_held")

# (again from the start: 120 Hz was just turned on)
func restart():
	_state = 0
	_t = 0.0
	set_process(true)

func _process(delta: float):
	if not wanted():
		set_process(false)
		return
	var cs = get_tree().current_scene
	if cs == null or not (cs.name == "Menu" or cs.name == "VRMenuHolder") or delta > 0.1 or not OS.is_window_focused():
		_state = 0 # (only a calm stretch of the menu says anything)
		_t = 0.0
		return
	_t += delta
	if _state == 0:
		if _t >= SETTLE_S:
			_state = 1
			_t = 0.0
			_frames = 0
			_proc_sum = 0.0
			_proc_n = 0
		return
	_frames += 1
	_proc_sum += Performance.get_monitor(Performance.TIME_PROCESS)
	_proc_n += 1
	if _t < MEASURE_S:
		return
	set_process(false)
	var fps: float = float(_frames) / _t
	var proc_ms: float = 1000.0 * _proc_sum / float(max(_proc_n, 1))
	# (0 / -1: change nothing, only report)
	var report: String = load("res://scripts/IosNative.gd").tune(0, -1.0)
	Rhythia.trail("120 Hz check: %.0f fps in the menu, scripts %.1f ms a frame, helper says: %s" % [fps, proc_ms, report.replace("\n", ", ") if report != "" else "(nothing)"])
	if fps >= ENOUGH_FPS:
		return
	Rhythia.set_meta("high_hz_held", true)
	Rhythia.apply_mobile_tuning() # (60 Hz for this run)
	Globals.notify(Globals.NOTIFY_WARN, why(report, fps, proc_ms) + " The game is at plain 60 Hz for now, so it doesn't feel delayed. Switch 120 Hz off and on in Settings, or start the game again, to try once more.", "120 Hz isn't getting through")

static func _value(report: String, key: String) -> String:
	for line in report.split("\n"):
		if line.begins_with(key + " "):
			return line.substr(key.length() + 1).strip_edges()
	return ""

# what holds it at 60, in plain words
static func why(report: String, fps: float, proc_ms: float) -> String:
	var shown := "The screen only showed %d frames a second with 120 Hz on." % int(round(fps))
	if _value(report, "lowpower") == "1":
		return shown + " Low Power Mode is on, and with it an iPhone holds its screen at 60 Hz: turn it off (Settings > Battery) to get 120."
	if _value(report, "plist120") == "0":
		return shown + " This installed app can't go above 60 Hz: install the latest chromia-ios.ipa once (in-app updates can't change that part)."
	var link := _value(report, "link")
	if link != "":
		var given := float(link.split(" ")[0])
		if given > 1.0 and given < 70.0:
			return shown + " iOS is only giving the game %d Hz right now. Check Settings > Accessibility > Motion > Limit Frame Rate, and that the phone isn't hot or saving battery." % int(round(given))
		if given >= 100.0:
			return shown + " The screen is at 120 Hz, but the game only finishes half of the frames in time on this phone%s." % ((" (its scripts alone take %.1f ms of the 8 ms a frame has)" % proc_ms) if proc_ms > 4.0 else "")
	return shown + " The usual causes: Low Power Mode (Settings > Battery), Settings > Accessibility > Motion > Limit Frame Rate, or an app installed before 120 Hz was supported (install the latest chromia-ios.ipa once, which also lets the game tell you which it is)."
