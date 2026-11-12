extends Reference

# Frame Smoothing's other half (Settings > Experimental > Frame Smoothing;
# NoteManager._update_draw_clock is the first): a frame rate the device holds.
#
# A headset or a 120 Hz phone that can't finish every frame in time shows some
# frames twice: the picture stutters, and far more plainly than a lower rate
# that is always met. So, with Frame Smoothing on, each song is checked when it
# ends (HitchLog counts the frames that came late for the rate the device was
# at). Too many late ones: the next songs run one rate lower (a headset's 120
# -> 90 -> 80 -> 72 Hz, an iPhone's 120 -> 60 Hz), kept in fs_cap_hz. After a
# few songs without late frames the next rate up is tried again; if that song
# drops frames it goes back down and waits longer before the next try.
#
# The rates asked for in the settings (Settings > VR > Refresh rate / Unlock
# refresh rate, the phones' 120 Hz) are the most it goes up to. Turning Frame
# Smoothing off, or changing one of those settings, lets go of the cap.

const LATE_TOO_MANY := 0.04 # share of a song's frames that came late: go down a rate
const LATE_CLEAN := 0.005 # under this the song counts as clean
const MIN_FRAMES := 1200 # (shorter songs say too little)
const CLEAN_SONGS := 5 # clean songs before the next rate up is tried

static func on() -> bool:
	return bool(Rhythia.get("frame_smoothing"))

# the rate held to (0: none)
static func cap() -> float:
	return float(Rhythia.get("fs_cap_hz")) if on() else 0.0

# the most the screen does (0: it doesn't say)
static func screen_top() -> float:
	var top := 0.0
	if OS.has_method("get_screen_refresh_rate"):
		top = float(OS.call("get_screen_refresh_rate"))
	if not (top >= 20.0): # (also when it isn't a number)
		top = 0.0
		# the iPhone helper reports it ("fps 120 (screen max 120)")
		var st := String(Rhythia.mobile_tuning_status)
		var at := st.find("screen max ")
		if at != -1:
			var digits := ""
			for i in range(at + 11, st.length()):
				if not st[i].is_valid_integer():
					break
				digits += st[i]
			top = float(digits) if digits != "" else 0.0
	return top

# The rate this device draws at now (0: it doesn't say).
static func current_hz() -> float:
	if Rhythia.vr:
		var cfg = Rhythia.get("vr_xr_config")
		if cfg != null and cfg.has_method("get_refresh_rate"):
			return float(cfg.get_refresh_rate())
		return 0.0
	var top: float = screen_top()
	if OS.has_feature("iOS"):
		# Godot draws at 60 there unless the native helper raised it (120 Hz)
		var asked := 60.0
		if Rhythia.mobile_high_hz and String(Rhythia.mobile_tuning_status) != "" and not (cap() > 0.0 and cap() < 100.0):
			asked = 120.0
		return min(asked, top) if top >= 20.0 else asked
	if not OS.has_feature("Android") and not OS.vsync_enabled:
		return 0.0 # (a computer without vsync: frames aren't paced by the screen)
	return top if top >= 20.0 else 0.0

# The rates this device can be put at, lowest first (fewer than two: it's not
# ours to change).
static func rates() -> Array:
	if Rhythia.vr:
		return load("res://vr/VRPlayer.gd").refresh_rates()
	if OS.has_feature("iOS") and Rhythia.mobile_high_hz and String(Rhythia.mobile_tuning_status) != "":
		if screen_top() > 100.0:
			return [60.0, 120.0]
	return []

# The most the settings ask for (0: the device's own rate).
static func wanted_hz() -> float:
	if Rhythia.vr:
		var w: float = load("res://vr/VRPlayer.gd").wanted_rate()
		if w <= 0.0 and Engine.has_meta("vr_base_hz"):
			w = float(Engine.get_meta("vr_base_hz"))
		return w
	return 120.0

static func _state() -> Dictionary:
	if not Engine.has_meta("fs_state"):
		Engine.set_meta("fs_state", {"clean": 0, "need": CLEAN_SONGS, "trial": false})
	return Engine.get_meta("fs_state")

# puts the device at the rate the settings and the cap give
static func apply():
	if Rhythia.vr:
		var vp = Rhythia.get("vr_player")
		if vp != null and is_instance_valid(vp) and vp.has_method("apply_refresh"):
			vp.apply_refresh()
	elif Rhythia.dev == "mobile":
		Rhythia.apply_mobile_tuning()

static func set_cap(hz: float):
	Rhythia.fs_cap_hz = hz
	apply()
	if Rhythia.has_method("save_settings"):
		Rhythia.call_deferred("save_settings")

# a setting that picks the rate was changed by hand: start over from it
static func let_go():
	Engine.set_meta("fs_state", {"clean": 0, "need": CLEAN_SONGS, "trial": false})
	if float(Rhythia.get("fs_cap_hz")) > 0.0:
		Rhythia.fs_cap_hz = 0.0
	apply()

# NoteManager, when a song ends: how its notes were drawn
static func song_notes(count: int, in_step: int, rough_real: float, rough_drawn: float):
	if count < 60:
		Engine.set_meta("fs_song_notes", {})
		return
	var d := {
		"in_step": float(in_step) / float(count),
		"real": rough_real / float(max(in_step, 1)),
		"drawn": rough_drawn / float(max(in_step, 1)),
	}
	Engine.set_meta("fs_song_notes", d)
	Rhythia.trail("frame smoothing: notes in step %d%% of %d frames, steps off by %.2f ms -> %.2f ms" % [int(round(d.in_step * 100.0)), count, d.real, d.drawn])

# HitchLog, when a song ends: frames, how many came late for the rate (over
# one and a half frames long), how long it ran, the rate it ran at
static func song_done(frames: int, late: int, secs: float, hz: float):
	if frames < 60 or secs <= 0.0:
		return
	var share: float = float(late) / float(frames)
	Engine.set_meta("fs_song", {"fps": float(frames) / secs, "hz": hz, "late": share, "frames": frames})
	if not on() or frames < MIN_FRAMES or hz <= 0.0 or Rhythia.render_fps > 0:
		return
	var list: Array = rates()
	if list.size() < 2:
		return
	var st: Dictionary = _state()
	if share > LATE_TOO_MANY:
		var lower := 0.0
		for r in list:
			if float(r) < hz - 0.5:
				lower = float(r)
		if st.trial:
			st.need = int(min(int(st.need) * 2, 40)) # (the try didn't hold: wait longer)
		st.clean = 0
		st.trial = false
		if lower > 0.0:
			set_cap(lower)
			Rhythia.trail("frame smoothing: %d%% of frames late at %d Hz, next songs at %d Hz" % [int(round(share * 100.0)), int(round(hz)), int(round(lower))])
			Globals.notify(Globals.NOTIFY_INFO, "That song dropped frames at %d Hz (%d%% came late), so the next ones run at %d Hz: steadier, and it looks smoother. The higher rate is tried again after a few clean songs." % [int(round(hz)), int(round(share * 100.0)), int(round(lower))], "Frame Smoothing")
	elif share < LATE_CLEAN:
		if st.trial:
			st.need = CLEAN_SONGS # (the try held)
		st.trial = false
		st.clean = int(st.clean) + 1
		if cap() > 0.0 and int(st.clean) >= int(st.need):
			var top: float = wanted_hz()
			var higher := 0.0
			for r in list:
				if higher <= 0.0 and float(r) > hz + 0.5 and (top <= 0.0 or float(r) <= top + 0.5):
					higher = float(r)
			st.clean = 0
			if higher > 0.0:
				st.trial = true
				# (the top rate again: no cap, the settings' own rate)
				set_cap(0.0 if (top > 0.0 and higher >= top - 0.5) else higher)
				Rhythia.trail("frame smoothing: clean songs at %d Hz, trying %d Hz" % [int(round(hz)), int(round(higher))])
	else:
		st.clean = 0
		st.trial = false

# One line for the settings page: how the last song went here.
static func summary() -> String:
	var out := PoolStringArray()
	if Engine.has_meta("fs_song"):
		var s: Dictionary = Engine.get_meta("fs_song")
		var line := "Last song: %d frames a second" % int(round(s.fps))
		if float(s.hz) > 0.0:
			line += " at %d Hz, %s of frames late" % [int(round(s.hz)), ("%.1f%%" % (float(s.late) * 100.0))]
		out.append(line + ".")
		if Engine.has_meta("fs_song_notes"):
			var n: Dictionary = Engine.get_meta("fs_song_notes")
			if n.has("in_step") and on() and float(n.in_step) < 0.5:
				out.append("Frames came too unevenly for the notes to be evened out (in step %d%% of the time)." % int(round(float(n.in_step) * 100.0)))
			elif n.has("in_step") and on():
				out.append("Notes drawn in step %d%% of the time (their steps were %.1f ms uneven, now %.1f ms)." % [int(round(float(n.in_step) * 100.0)), float(n.real), float(n.drawn)])
	var c: float = cap()
	if c > 0.0:
		out.append("Held at %d Hz for now: the higher rate kept dropping frames. It is tried again after a few clean songs." % int(round(c)))
	return out.join(" ")
