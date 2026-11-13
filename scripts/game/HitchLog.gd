extends Node

# Slow frames while playing a map go to the trail (logs/trail.txt), with what
# was going on, so a stutter can be traced: how long the frame took, the
# scripts' share of it, draw calls, objects, and the web requests running.
# At most MAX_LOGGED a song (a slow PC isn't flooded).

const SLOW_SEC := 0.05
const MAX_LOGGED := 40

var _logged := 0
var _skip := 30 # (the first frames of a song are slow anyway)

# The whole song in one line when it's left ("song perf: ..."): how many
# frames, the average rate, how many were slow and the slowest, the scripts'
# share, and what was on (VR, its refresh rate, the trail). With Settings >
# Experimental > Always show crash logs, the next start shows it with a Copy
# report button, so "it lags" comes with numbers.
var _frames := 0
var _time := 0.0
var _over_20 := 0
var _over_33 := 0
var _over_50 := 0
var _worst := 0.0
var _script_sum := 0.0
var _script_n := 0
var _script_at := 0.0
# frames that came late for the rate the device is at (over one and a half
# frames long), for Frame Smoothing's steady rate (SteadyRate.song_done)
const SteadyRate = preload("res://scripts/game/SteadyRate.gd")
var _hz := 0.0
var _late := 0
var _hz_frames := 0

func _exit_tree():
	if _frames < 60 or _time <= 0.0:
		return
	var what := PoolStringArray()
	if Rhythia.vr:
		var hz := 0.0
		var cfg = Rhythia.get("vr_xr_config")
		if cfg != null and cfg.has_method("get_refresh_rate"):
			hz = float(cfg.get_refresh_rate())
		what.append("VR %s Hz%s, render scale %s, foveation %s" % [str(hz) if hz > 0 else "?", " (unlocked)" if Rhythia.vr_refresh_unlock else "", str(Rhythia.vr_render_scale), str(Rhythia.vr_foveation)])
	if Rhythia.cursor_trail:
		what.append("%s trail, detail %s, time %s" % ["smart" if Rhythia.smart_trail else "classic", str(Rhythia.trail_detail), str(Rhythia.trail_time)])
	else:
		what.append("no trail")
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null and bool(lm.get("watch_mode")):
		what.append("spectating")
	if Rhythia.replaying:
		what.append("replay")
	if _hz > 0.0 and _hz_frames > 0:
		what.append("%d Hz, late frames %.1f%%%s" % [int(round(_hz)), 100.0 * float(_late) / float(_hz_frames), (", held at %d Hz" % int(round(SteadyRate.cap()))) if SteadyRate.cap() > 0.0 else ""])
	Rhythia.trail("song perf: %d frames in %d s (%.0f fps), over 20 ms: %d, over 33 ms: %d, over 50 ms: %d, worst %d ms, scripts %.1f ms a frame; %s" % [
		_frames, int(_time), float(_frames) / _time, _over_20, _over_33, _over_50, int(_worst * 1000.0),
		(_script_sum / _script_n) if _script_n > 0 else 0.0, what.join("; ")])
	SteadyRate.song_done(_hz_frames if _hz > 0.0 else _frames, _late, _time, _hz)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func _process(delta):
	if _skip > 0:
		_skip -= 1
		return
	if not get_tree().paused:
		_frames += 1
		_time += delta
		if delta > 0.02:
			_over_20 += 1
		if delta > 0.0333:
			_over_33 += 1
		if delta > SLOW_SEC:
			_over_50 += 1
		if delta > _worst:
			_worst = delta
		if _hz <= 0.0 and _frames == 1:
			_hz = SteadyRate.current_hz()
		if _hz > 0.0:
			_hz_frames += 1
			if delta > 1.5 / _hz:
				_late += 1
		# (the engine keeps the scripts' time as a reading renewed once a second)
		_script_at += delta
		if _script_at >= 1.0:
			_script_at = 0.0
			_hz = SteadyRate.current_hz()
			_script_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			_script_n += 1
	if delta < SLOW_SEC or _logged >= MAX_LOGGED or get_tree().paused:
		return
	_logged += 1
	var http := 0
	for n in [get_node_or_null("/root/LobbyManager"), get_node_or_null("/root/Rhythia"), get_node_or_null("/root/Online")]:
		if n != null:
			for c in n.get_children():
				if c is HTTPRequest and c.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
					http += 1
	Rhythia.trail("hitch %d ms (scripts %.1f ms, physics %.1f ms, draw calls %d, objects %d, web requests %d, fps %d)" % [
		int(delta * 1000.0),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		-1 if Rhythia.vr else int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)), # (VR: the reading waits for the render thread)
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		http,
		int(Performance.get_monitor(Performance.TIME_FPS)),
	])
