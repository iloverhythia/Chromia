extends Node

# Streaming Mode (Settings > Replays & Misc > Experimental): room for Discord,
# OBS and the like.
#
# Sharing your screen means another program copies and encodes every picture
# on the same graphics card the game draws with. With no frame limit the game
# takes all of the card, the other program has to wait its turn, and both the
# game and the stream stutter. With this on, the game draws at three quarters
# of what your computer manages and leaves the rest free.
#
# How: once for the menu and once for songs it looks at the frame rate you get
# with your own settings for a second, then sets the frame limit to 75% of
# that (never above your own limit). If the game then can't even reach that
# (the other program takes more than a quarter), the limit goes down a bit
# more. It looks again every quarter of an hour, and when you change your
# frame limit. Your own Max FPS setting is kept (Rhythia.stream_user_fps) and
# comes back when this is turned off. Nothing about the game itself changes:
# it's a frame limit, as Max FPS is.
#
# Not with VSync on (the screen already holds the frame rate), in VR, on
# phones or in the browser.

const SHARE := 0.75
const LOWEST := 30
const MEASURE_S := 1.0
const WINDOW_S := 2.0
const SETTLE_S := 1.5 # (after a scene change: loading, the first frames)
const AGAIN_S := 900.0

var _caps := {} # "menu" / "song" -> [limit, when measured (s)]
var _kind := ""
var _state := 0 # 0 waiting, 1 measuring, 2 holding
var _t := 0.0
var _frames := 0
var _hitch := false
var _applied := -1
var _scene_id := 0
var _clock := 0.0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func usable() -> bool:
	return bool(Rhythia.stream_mode) and not Rhythia.vr and Rhythia.dev != "mobile" \
		and not OS.has_feature("JavaScript") and Rhythia.render_fps <= 0 and not OS.vsync_enabled \
		and not Rhythia.has_meta("no_delay_saved")

func _release():
	if Rhythia.stream_user_fps >= 0:
		if Engine.target_fps == _applied:
			Engine.target_fps = Rhythia.stream_user_fps
		Rhythia.stream_user_fps = -1
	_applied = -1
	_state = 0
	_t = 0.0

func _set_limit(v: int):
	_applied = v
	Engine.target_fps = v

func _process(delta: float):
	_clock += delta
	if not usable():
		if Rhythia.stream_user_fps >= 0:
			_release()
			Rhythia.trail("streaming mode: let go of the frame limit")
		return
	var cs = get_tree().current_scene
	var id: int = cs.get_instance_id() if cs != null else 0
	if id != _scene_id:
		# another screen: its own limit (kept from last time, or measured)
		_scene_id = id
		var kind := "song" if (cs != null and cs.name == "Song") else "menu"
		if kind != _kind or _state != 2:
			_kind = kind
			if Rhythia.stream_user_fps < 0:
				Rhythia.stream_user_fps = Engine.target_fps
			_state = 0
		_t = -SETTLE_S
		_frames = 0
		_hitch = false
		return
	if Rhythia.stream_user_fps < 0:
		Rhythia.stream_user_fps = Engine.target_fps
	elif _applied >= 0 and Engine.target_fps != _applied:
		# the frame limit was changed elsewhere (Max FPS, a profile): that's
		# your own limit now, and everything is measured again
		Rhythia.stream_user_fps = Engine.target_fps
		_caps.clear()
		_state = 0
		_t = -0.3
	_t += delta
	if _t < 0.0:
		_frames = 0
		_hitch = false
		return
	if not OS.is_window_focused() or OS.window_minimized:
		_t = 0.0
		_frames = 0
		_hitch = false
		return
	_frames += 1
	if delta > 0.1:
		_hitch = true
	if _state == 0:
		var known = _caps.get(_kind)
		if known != null and _clock - float(known[1]) < AGAIN_S:
			_set_limit(int(known[0]))
			_state = 2
		else:
			_set_limit(Rhythia.stream_user_fps) # (your own settings, to see what the computer does)
			_state = 1
		_t = 0.0
		_frames = 0
		_hitch = false
	elif _state == 1:
		if _t >= MEASURE_S:
			if _hitch:
				_t = 0.0; _frames = 0; _hitch = false # (a stall in it: again)
				return
			var fps: float = float(_frames) / _t
			var limit: int = int(max(LOWEST, round(fps * SHARE)))
			if Rhythia.stream_user_fps > 0:
				limit = int(min(limit, Rhythia.stream_user_fps))
			_caps[_kind] = [limit, _clock]
			_set_limit(limit)
			Rhythia.trail("streaming mode: %s runs at %d fps here, limit %d" % [_kind, int(round(fps)), limit])
			_state = 2
			_t = 0.0; _frames = 0; _hitch = false
	else:
		if _t >= WINDOW_S:
			var fps2: float = float(_frames) / _t
			var had_hitch: bool = _hitch
			_t = 0.0; _frames = 0; _hitch = false
			if not had_hitch and _applied > LOWEST and fps2 < float(_applied) * 0.9:
				# can't even reach the limit: something else has more than its share
				var lower: int = int(max(LOWEST, round(fps2 * 0.85)))
				if lower < _applied:
					_caps[_kind] = [lower, _clock]
					_set_limit(lower)
					Rhythia.trail("streaming mode: only %d fps under the limit, limit %d now" % [int(round(fps2)), lower])
			elif _clock - float(_caps.get(_kind, [0, _clock])[1]) >= AGAIN_S and _kind == "menu":
				_state = 0 # (looked at again now and then; in a song only at its start)
