extends Node

# The Performance Logger (Settings > Video & Audio > Performance Logger): for
# lag and stutters that leave no crash behind.
#
# While it's on, every frame's time is measured. A frame that takes much
# longer than the ones around it (a hitch: over HITCH_MIN_MS and over
# HITCH_TIMES x the usual frame) is written down at once with what can be told
# about it:
#  - how long it took, and how much of that was the game's scripts and its
#    physics; the rest is drawing, the graphics driver, Windows or another
#    program (the line says which it looks like);
#  - where: the menu or a map (and the time in the song);
#  - what the frame drew (draw calls, objects, material and shader changes:
#    a first-time shader is compiled while drawing, a classic stutter);
#  - nodes and objects made since the frame before, memory jumps;
#  - the step the game had named (Rhythia.doing) and the background jobs;
#  - a window that lost focus or a scene that changed (those are said, so a
#    normal hitch isn't taken for a problem).
# Every 5 seconds a summary line: frames per second, the usual and the worst
# frame, draw calls, objects, memory.
#
# The lines go to user://logs/performance.txt (the whole session) and, the
# hitches and the start, to the game's trail too, so Settings > Crash Reports
# > "Send this session's log" sends them to the developers (Savia.session_report
# also adds the performance file's last lines).

const FILE := "user://logs/performance.txt"
const HITCH_MIN_MS := 34.0   # (a frame longer than two at 60 Hz...)
const HITCH_TIMES := 3.0     # (...and three times the usual one)
const SUMMARY_SEC := 5.0
const TRAIL_HITCHES_PER_SEC := 3

var _f: File = null
var _last_us := 0
var _gaps := []          # the last frames' times (ms), for the usual frame
var _usual := 16.7
var _frames := 0
var _sum_frames := 0
var _sum_ms := 0.0
var _sum_worst := 0.0
var _sum_hitches := 0
var _sum_at := 0
var _nodes_added := 0
var _nodes_at_frame := 0
var _objects_before := 0
var _mem_before := 0
var _scene_id := 0
var _focused := true
var _trail_sec := 0
var _trail_in_sec := 0
var _song_hitches := []  # [ms, gap, song ms, kind] in the current map
var _in_map := false
var _spawn: WeakRef = null
# the game's own time, measured here (Performance's TIME_PROCESS lags behind by
# several frames): this node runs first in every frame and PerfLogEnd.gd last
var _start_us := 0      # when this frame's scripts began
var _end_us := 0        # when the last frame's scripts ended (PerfLogEnd)
var _phys_start_us := 0
var _phys_us := 0       # physics time since the last frame's scripts ended
var _end_node: Node = null

func _physics_process(_d):
	_phys_start_us = OS.get_ticks_usec()

func _physics_end():
	if _phys_start_us > 0:
		_phys_us += OS.get_ticks_usec() - _phys_start_us
		_phys_start_us = 0

# (one at a time: it's added a frame later, so a second start in the same
# frame, e.g. the settings read again, finds the one on its way)
static func _current():
	if Engine.has_meta("perf_log_node"):
		var n = Engine.get_meta("perf_log_node")
		if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
			return n
	return null

static func start(tree: SceneTree):
	if _current() != null:
		return
	var n: Node = load("res://scripts/PerfLog.gd").new()
	n.name = "PerfLog"
	Engine.set_meta("perf_log_node", n)
	tree.root.call_deferred("add_child", n)

static func stop(_tree: SceneTree):
	var n = _current()
	if n == null:
		return
	Engine.set_meta("perf_log_node", null)
	if n.is_inside_tree():
		n.queue_free()
	else:
		n.call_deferred("free") # (not added yet: gone once its add has happened)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = -100000 # (first in every frame: the gap since the last frame began)
	Directory.new().make_dir_recursive(Globals.p("user://logs"))
	_f = File.new()
	if _f.open(Globals.p(FILE), File.WRITE) != OK:
		_f = null
	get_tree().connect("node_added", self, "_on_node_added")
	_last_us = OS.get_ticks_usec()
	_start_us = _last_us
	_end_us = _last_us
	_end_node = load("res://scripts/PerfLogEnd.gd").new()
	_end_node.name = "PerfLogEnd"
	_end_node.log_node = self
	get_parent().call_deferred("add_child", _end_node)
	_sum_at = OS.get_ticks_msec()
	_objects_before = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_mem_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_write(_setup_text(), true)

func _exit_tree():
	if get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().disconnect("node_added", self, "_on_node_added")
	if _end_node != null and is_instance_valid(_end_node):
		_end_node.queue_free()
	_write("performance logger off", true)
	if _f != null:
		_f.close()
		_f = null

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		_focused = false
		_write("the window lost focus (another program in front): frames can be slow on purpose now")
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		_focused = true
		_write("the window has focus again")

func _on_node_added(_n):
	_nodes_added += 1

# what this computer and the game's graphics settings are
func _setup_text() -> String:
	var hz := "?"
	if OS.has_method("get_screen_refresh_rate"):
		var r := float(OS.call("get_screen_refresh_rate"))
		if r > 0.0 and not is_nan(r):
			hz = str(stepify(r, 0.1))
	var lines := [
		"performance logger on (%s, %s %s)" % [ProjectSettings.get_setting("application/config/version"), OS.get_name(), OS.get_model_name()],
		"  graphics: %s, %s (%s); %d CPU threads" % [VisualServer.get_video_adapter_name(), VisualServer.get_video_adapter_vendor(), "GLES3" if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3 else "GLES2", OS.get_processor_count()],
		"  screen: %s at %s Hz, window %s%s, vsync %s (via compositor %s), FPS limit %s" % [str(OS.get_screen_size()), hz, str(OS.window_size), " fullscreen" if OS.window_fullscreen else (" borderless" if OS.window_borderless else ""), str(OS.vsync_enabled), str(OS.vsync_via_compositor), str(Engine.target_fps) if Engine.target_fps > 0 else "none"],
		"  game: Max FPS mode %s, No Delay %s, Frame Smoothing %s, glow %s, bloom %s, background %s" % [
			str(Rhythia.get("max_fps_mode")), str(Rhythia.get("pc_no_delay")), str(Rhythia.get("frame_smoothing")), str(Rhythia.get("glow")), str(Rhythia.get("bloom")),
			Rhythia.selected_space.name if Rhythia.get("selected_space") != null else "?"],
		"  power: %s" % ["unknown", "on battery", "no battery", "charging", "charged"][int(clamp(OS.get_power_state(), 0, 4))],
	]
	return PoolStringArray(lines).join("\n")

func _write(line: String, to_trail: bool = false):
	var text := "[%8.2fs] %s" % [OS.get_ticks_msec() / 1000.0, line]
	if _f != null:
		_f.store_line(text)
		_f.flush()
	if to_trail:
		Rhythia.trail("perf: " + line.replace("\n", " |"))

func _where() -> String:
	if not Rhythia.in_map:
		return "menu"
	var sp = _spawn.get_ref() if _spawn != null else null
	if sp == null or not is_instance_valid(sp):
		var cs = get_tree().current_scene
		sp = cs.get_node_or_null("Game/Spawn") if cs != null else null
		_spawn = weakref(sp) if sp != null else null
	if sp != null and "ms" in sp:
		return "map at %.1f s" % (float(sp.ms) / 1000.0)
	return "map"

func _song_ms() -> float:
	var sp = _spawn.get_ref() if _spawn != null else null
	return float(sp.ms) if sp != null and is_instance_valid(sp) and "ms" in sp else -1.0

func _process(_delta):
	var now_us := OS.get_ticks_usec()
	var gap := (now_us - _last_us) / 1000.0
	_last_us = now_us
	_frames += 1
	# the frame that just ended: its scripts (start to PerfLogEnd), the physics
	# steps run since, and the rest (drawing, the graphics driver, waiting for
	# the screen or the FPS limit, Windows)
	var script_ms: float = max(0.0, (_end_us - _start_us) / 1000.0)
	var physics_ms: float = _phys_us / 1000.0
	_phys_us = 0
	_start_us = now_us
	var nodes := _nodes_added - _nodes_at_frame
	_nodes_at_frame = _nodes_added
	var cs = get_tree().current_scene
	var scene_id: int = cs.get_instance_id() if cs != null else 0
	var scene_changed: bool = scene_id != _scene_id
	_scene_id = scene_id
	# into a map / out of it: a line, and the map's worst hitches at the end
	if Rhythia.in_map != _in_map:
		_in_map = Rhythia.in_map
		if _in_map:
			_song_hitches = []
			_spawn = null
			_write("map started: %s (FPS limit %s, vsync %s, No Delay %s)" % [Rhythia.selected_song.name if Rhythia.get("selected_song") != null else "?",
				str(Engine.target_fps) if Engine.target_fps > 0 else "none", str(OS.vsync_enabled), str(Rhythia.no_delay_active()) if Rhythia.has_method("no_delay_active") else "?"], true)
		else:
			_map_summary()
	# the usual frame: the middle of the last 120
	_gaps.append(gap)
	if _gaps.size() > 120:
		_gaps.pop_front()
	if _frames % 30 == 0 and _gaps.size() >= 20:
		var s := _gaps.duplicate()
		s.sort()
		_usual = s[s.size() / 2]
	_sum_frames += 1
	_sum_ms += gap
	_sum_worst = max(_sum_worst, gap)
	if _frames > 30 and gap > HITCH_MIN_MS and gap > _usual * HITCH_TIMES:
		_hitch(gap, script_ms, physics_ms, nodes, scene_changed)
	var now_ms := OS.get_ticks_msec()
	if now_ms - _sum_at >= SUMMARY_SEC * 1000.0:
		_summary(now_ms)

func _hitch(gap: float, script_ms: float, physics_ms: float, nodes: int, scene_changed: bool):
	_sum_hitches += 1
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var rest: float = max(0.0, gap - script_ms - physics_ms)
	var kind := "drawing / graphics driver / waiting / Windows or another program (not the game's scripts)"
	var short := "drawing or other"
	if script_ms >= gap * 0.5:
		kind = "the game's scripts"
		short = "scripts"
	elif physics_ms >= gap * 0.5:
		kind = "physics"
		short = "physics"
	var why := []
	if scene_changed:
		why.append("a scene change (loading)")
	if not _focused:
		why.append("the window isn't focused")
	var shaders := int(Performance.get_monitor(Performance.RENDER_SHADER_CHANGES_IN_FRAME))
	var fw = Rhythia.get("_freeze_watch")
	var step := ""
	if fw != null and is_instance_valid(fw):
		# (a step going on now, or one that began or ended during this frame)
		if String(fw.get("_doing")) != "":
			step = String(fw.get("_doing"))
		elif String(fw.get("_last")) != "" and OS.get_ticks_msec() - int(fw.get("_doing_at")) <= gap + 20:
			step = "just before: " + String(fw.get("_last"))
	var jobs := String(Rhythia.background_jobs()) if Rhythia.has_method("background_jobs") else ""
	var line := "HITCH %.0f ms (usual %.1f) in %s: scripts %.1f ms, physics %.1f ms, other %.1f ms -> looks like %s%s" % [
		gap, _usual, _where(), script_ms, physics_ms, rest, kind, (" [" + PoolStringArray(why).join(", ") + "]") if not why.empty() else ""]
	line += "\n    drew: %d draw calls, %d objects, %d material changes, %d shader changes%s; made %d nodes, objects %+d, memory %+.1f MB%s%s" % [
		int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_MATERIAL_CHANGES_IN_FRAME)), shaders, " (new shaders being compiled?)" if shaders > 30 else "",
		nodes, objects - _objects_before, (mem - _mem_before) / 1048576.0,
		("; step: " + step) if step != "" else "", ("; background: " + jobs) if jobs != "" and jobs != "none" else ""]
	_objects_before = objects
	_mem_before = mem
	if _in_map:
		_song_hitches.append([gap, _song_ms(), short])
	_write(line)
	# (to the trail as well, a few a second at most: a run of them is summed up)
	var sec := OS.get_ticks_msec() / 1000
	if sec != _trail_sec:
		_trail_sec = sec
		_trail_in_sec = 0
	_trail_in_sec += 1
	if _trail_in_sec <= TRAIL_HITCHES_PER_SEC:
		Rhythia.trail("perf: " + line.replace("\n    ", " | "))

func _summary(now_ms: int):
	var secs: float = (now_ms - _sum_at) / 1000.0
	_sum_at = now_ms
	if _sum_frames == 0:
		return
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_write("%s: %.0f fps, usual frame %.1f ms, worst %.0f ms, %d hitch(es); %d draw calls, %d objects drawn, %d objects, %d nodes, %d orphan nodes, memory %.0f MB" % [
		_where(), _sum_frames / secs, _usual, _sum_worst, _sum_hitches,
		int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME)),
		objects, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), mem / 1048576.0])
	_objects_before = objects
	_mem_before = mem
	_sum_frames = 0
	_sum_ms = 0.0
	_sum_worst = 0.0
	_sum_hitches = 0

func _map_summary():
	if _song_hitches.empty():
		_write("map ended: no hitches", true)
		return
	var worst := _song_hitches.duplicate()
	worst.sort_custom(self, "_by_gap")
	var parts := []
	for i in range(min(5, worst.size())):
		parts.append("%.0f ms at %.1f s (%s)" % [worst[i][0], float(worst[i][1]) / 1000.0, String(worst[i][2])])
	_write("map ended: %d hitch(es); worst: %s" % [_song_hitches.size(), PoolStringArray(parts).join(", ")], true)

func _by_gap(a, b) -> bool:
	return float(a[0]) > float(b[0])

# the file's last lines (Savia.session_report adds them)
static func tail(lines: int) -> String:
	var f := File.new()
	if f.open(Globals.p(FILE), File.READ) != OK:
		return ""
	var all := f.get_as_text().strip_edges().split("\n")
	f.close()
	var out := []
	for i in range(max(0, all.size() - lines), all.size()):
		out.append(all[i])
	return PoolStringArray(out).join("\n")
