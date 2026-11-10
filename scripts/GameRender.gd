extends Node

# Save video > In the game (PC): the game plays the run again and makes the
# MP4 itself, one frame at a time (RenderCapture.gd), so it's smooth whatever
# the computer does meanwhile, at the game window's size. Saved in your
# Videos folder (Videos/Chromia).
#
# ffmpeg makes the MP4: one on the PATH, else the copy the game downloads
# once into user://tools (the ffmpeg-static build the Savia server uses, a
# ~30 MB download, only kept if its sha256 is the one below).
# Each frame is read back from the screen and sent to ffmpeg over a local
# connection (127.0.0.1); the sound is put together after: the other sounds
# (hitsounds, misses...) laid out here, the music cut and placed by ffmpeg.

const FFMPEG_URL := "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-win32-x64.gz"
const FFMPEG_GZ_SHA256 := "450d66226c79405c724e821f291cab0911e934bfa9fa2231adcab587f3e07b50"
const TOOLS := "user://tools"
const WORK := "user://render"
const FPS := 60
const RATE := 48000
const MAX_LANES := 24

var _replay_file := ""
var _song = null
var _title := ""
var busy := false

var _ffmpeg := ""
var _cap = null
var _tcp: StreamPeerTCP = null
var _size := Vector2.ZERO
var _thread: Thread = null
var _thread_done := false
var _thread_result := []
var _old_title := ""
var _logo: CanvasLayer = null
var _failed := ""

static func available() -> bool:
	return OS.get_name() == "Windows" and not Rhythia.vr

# does it need the ffmpeg download first (for the menu's wording)
static func needs_download() -> bool:
	return not File.new().file_exists(ProjectSettings.globalize_path(TOOLS + "/ffmpeg.exe"))

static func start(tree: SceneTree, replay_file: String, song, title: String):
	var cur = tree.root.get_node_or_null("GameRender")
	if cur != null and cur.busy:
		Globals.notify(Globals.NOTIFY_INFO, "Already making a video.", "Save video")
		return
	if cur != null:
		cur.queue_free()
	var n = load("res://scripts/GameRender.gd").new()
	n.name = "GameRender"
	n._replay_file = replay_file
	n._song = song
	n._title = title
	tree.root.add_child(n)
	n.call_deferred("_go")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

# ── ffmpeg ──
func _runs(bin: String) -> bool:
	var out := []
	return OS.execute(bin, PoolStringArray(["-hide_banner", "-version"]), true, out) == 0

# -> the ffmpeg to use ("" when there's none). Always yields.
func _find_ffmpeg():
	yield(get_tree(), "idle_frame")
	var own := _abs(TOOLS + "/ffmpeg.exe")
	if File.new().file_exists(own) and _runs(own):
		return own
	var out := []
	if OS.execute("where", PoolStringArray(["ffmpeg"]), true, out) == 0 and out.size() > 0:
		var lines: PoolStringArray = String(out[0]).strip_edges().split("\n", false)
		var first: String = lines[0].strip_edges() if lines.size() > 0 else ""
		if first != "" and _runs(first):
			return first
	_set_title("downloading ffmpeg (once)")
	Globals.notify(Globals.NOTIFY_INFO, "Downloading ffmpeg (about 30 MB, only this once)...", "Save video")
	Directory.new().make_dir_recursive(TOOLS)
	var gz := _abs(TOOLS + "/ffmpeg.gz")
	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_file = gz
	http.timeout = 300
	add_child(http)
	if http.request(FFMPEG_URL) != OK:
		http.queue_free()
		return ""
	var res: Array = yield(http, "request_completed")
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		Directory.new().remove(gz)
		return ""
	# only the expected file is ever run
	if File.new().get_sha256(gz) != FFMPEG_GZ_SHA256:
		Directory.new().remove(gz)
		_failed = "The ffmpeg download wasn't the expected file."
		return ""
	var f := File.new()
	if f.open(gz, File.READ) != OK:
		return ""
	var packed := f.get_buffer(f.get_len())
	f.close()
	# (a gzip ends with its unpacked size)
	var n := packed.size()
	var size: int = packed[n - 4] | (packed[n - 3] << 8) | (packed[n - 2] << 16) | (packed[n - 1] << 24)
	var bin := packed.decompress(size, File.COMPRESSION_GZIP)
	packed = PoolByteArray()
	if bin.size() != size:
		Directory.new().remove(gz)
		return ""
	if f.open(own, File.WRITE) != OK:
		return ""
	f.store_buffer(bin)
	f.close()
	Directory.new().remove(gz)
	return own if _runs(own) else ""

# ffmpeg with these arguments, on a thread (it can take a while) -> [exit code, its messages]. Always yields.
func _ffmpeg_run(args: Array):
	yield(get_tree(), "idle_frame")
	_thread_done = false
	_thread_result = []
	_thread = Thread.new()
	_thread.start(self, "_thread_run", args)
	while not _thread_done:
		yield(get_tree(), "idle_frame")
	_thread.wait_to_finish()
	_thread = null
	return _thread_result

func _thread_run(args: Array):
	var out := []
	var code := OS.execute(_ffmpeg, PoolStringArray(args), true, out, true)
	_thread_result = [code, PoolStringArray(out).join("\n")]
	_thread_done = true

# ── making it ──
func _set_title(what: String):
	OS.set_window_title("Chromia - making your video: %s" % what)

func _go():
	busy = true
	_failed = ""
	_old_title = String(ProjectSettings.get_setting("application/config/name"))
	_ffmpeg = yield(_find_ffmpeg(), "completed")
	if _ffmpeg == "":
		return _fail(_failed if _failed != "" else "Couldn't get ffmpeg, which makes the video (check your internet).")
	_clean_work()
	Directory.new().make_dir_recursive(WORK)
	# the picture's size and kind, from a frame of the screen now
	yield(VisualServer, "frame_post_draw")
	var probe: Image = get_viewport().get_texture().get_data()
	_size = probe.get_size()
	var pix := "rgba" if probe.get_format() == Image.FORMAT_RGBA8 else "rgb24"
	if probe.get_format() != Image.FORMAT_RGBA8 and probe.get_format() != Image.FORMAT_RGB8:
		return _fail("The screen's picture can't be read here.")
	_pix_format = probe.get_format()
	probe = null
	# ffmpeg waits for the frames on a local port
	var port := 20000 + randi() % 30000
	var video := _abs(WORK + "/video.mp4")
	var args := ["-hide_banner", "-loglevel", "error", "-y",
		"-f", "rawvideo", "-pix_fmt", pix, "-video_size", "%dx%d" % [_size.x, _size.y], "-framerate", str(FPS),
		"-i", "tcp://127.0.0.1:%d?listen=1&listen_timeout=15000" % port,
		"-vf", "vflip,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-movflags", "+faststart", video]
	_thread_done = false
	_thread_result = []
	_thread = Thread.new()
	_thread.start(self, "_thread_run", args)
	_tcp = StreamPeerTCP.new()
	var t0 := OS.get_ticks_msec()
	var connected := false
	while OS.get_ticks_msec() - t0 < 10000 and not _thread_done:
		if _tcp.get_status() == StreamPeerTCP.STATUS_NONE or _tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
			_tcp = StreamPeerTCP.new()
			_tcp.connect_to_host("127.0.0.1", port)
		if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			connected = true
			break
		yield(get_tree(), "idle_frame")
	if not connected:
		_end_ffmpeg()
		return _fail("ffmpeg didn't start." + _ffmpeg_said())
	_tcp.set_no_delay(true)
	# the run, played again
	Globals.notify(Globals.NOTIFY_INFO, "Making your video: the game plays your run again. Leave it running; the window's title shows how far it is.", "Save video")
	yield(get_tree().create_timer(0.3), "timeout")
	Rhythia.rendering = true
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = _replay_file
	_waiting = true
	_seen_loader = false
	_game_scene = null
	_ending_at = -1
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

var _pix_format := Image.FORMAT_RGBA8
var _waiting := false
var _seen_loader := false
var _game_scene = null
var _ending_at := -1 # the frame the song ended at

func _process(_delta):
	if not busy:
		return
	var cur = get_tree().current_scene
	if cur == null:
		return
	var file := String(cur.filename).to_lower()
	if _waiting:
		if file.find("songload") != -1:
			_seen_loader = true
			return
		if not _seen_loader:
			return
		_waiting = false
		if cur.get_node_or_null("Game/Spawn") == null:
			# (the replay couldn't be played: back in the menu)
			Rhythia.rendering = false
			return _fail("The replay couldn't be played.")
		_game_scene = cur
		_show_logo(true)
		_cap = load("res://scripts/RenderCapture.gd").new()
		add_child(_cap)
		_cap.connect("frame_drawn", self, "_on_frame_drawn")
		_cap.begin(FPS, false)
		return
	if _cap == null or _game_scene == null:
		return
	if cur != _game_scene:
		# back in the menu: the song is over (or it was left)
		_finish(_ending_at >= 0)
		return
	var g = cur.get_node_or_null("Game")
	var spawn = cur.get_node_or_null("Game/Spawn")
	if g != null and spawn != null:
		var last := float(g.get("last_ms"))
		if last > 0:
			_set_title("%d%%" % int(clamp(float(spawn.get("ms")) / last, 0.0, 1.0) * 100))
		if bool(g.get("ending")) and _ending_at < 0:
			_ending_at = _cap.frame
	# a moment after the end, then it's done
	if _ending_at >= 0 and _cap.frame >= _ending_at + int(FPS * 1.2):
		_finish(true)

# each frame as it's drawn, to ffmpeg
func _on_frame_drawn(_i: int):
	if _tcp == null or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var img: Image = get_viewport().get_texture().get_data()
	if img.get_size() != _size:
		# (the window changed size: the video keeps its own)
		img.resize(int(_size.x), int(_size.y), Image.INTERPOLATE_BILINEAR)
	if img.get_format() != _pix_format:
		img.convert(_pix_format)
	_tcp.put_data(img.get_data())

func _show_logo(on: bool):
	if not on:
		if _logo != null and is_instance_valid(_logo):
			_logo.queue_free()
		_logo = null
		return
	_logo = CanvasLayer.new()
	_logo.layer = 125
	add_child(_logo)
	var h: float = get_viewport().get_visible_rect().size.y
	var side := round(h * 0.075)
	var margin := round(h * 0.03)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/images/branding/icon.png")
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left = 1.0
	logo.anchor_top = 1.0
	logo.anchor_right = 1.0
	logo.anchor_bottom = 1.0
	logo.margin_left = -side - margin
	logo.margin_top = -side - margin
	logo.margin_right = -margin
	logo.margin_bottom = -margin
	logo.modulate = Color(1, 1, 1, 0.8)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(logo)

# ffmpeg stopped: the connection closed (it gives up by itself when nothing
# connects: listen_timeout); waits a few seconds at most
func _end_ffmpeg():
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	if _thread != null:
		var t0 := OS.get_ticks_msec()
		while not _thread_done and OS.get_ticks_msec() - t0 < 5000:
			OS.delay_msec(20)
		if _thread_done:
			_thread.wait_to_finish()
		_thread = null

func _ffmpeg_said() -> String:
	var said: String = String(_thread_result[1]).strip_edges() if _thread_result.size() > 1 else ""
	return ("\n" + said.substr(0, 300)) if said != "" else ""

var _finishing := false
func _finish(ok: bool):
	if _finishing:
		return
	_finishing = true
	var data: Dictionary = _cap.end()
	_cap.queue_free()
	_cap = null
	_show_logo(false)
	Rhythia.rendering = false
	OS.set_window_title(_old_title)
	if get_tree().current_scene == _game_scene:
		get_tree().paused = false
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")
	_game_scene = null
	if not ok:
		_end_ffmpeg()
		_clean_work()
		busy = false
		Globals.notify(Globals.NOTIFY_WARN, "The video was stopped before the end.", "Save video")
		return
	# the picture: ffmpeg finishes once the connection closes
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	while not _thread_done:
		yield(get_tree(), "idle_frame")
	_thread.wait_to_finish()
	_thread = null
	if int(_thread_result[0]) != 0:
		return _fail("ffmpeg couldn't make the picture." + _ffmpeg_said())
	Globals.notify(Globals.NOTIFY_INFO, "Putting the sound on...", "Save video")
	var out_path: String = yield(_make_sound(data), "completed")
	_clean_work()
	busy = false
	if out_path == "":
		return
	Globals.notify(Globals.NOTIFY_SUCCEED, "Saved in Videos/Chromia: %s" % out_path.get_file(), "Save video")
	OS.shell_open(out_path.get_base_dir())

# ── the sound ──
# -> the finished video's path ("" when it failed). Always yields.
func _make_sound(data: Dictionary):
	yield(get_tree(), "idle_frame")
	var dur := float(data.frames) / float(data.fps)
	var total := int(ceil(dur * RATE))
	# the sounds' own files
	var paths := {}
	for sid in data.files.keys():
		var info: Dictionary = data.files[sid]
		var bytes: PoolByteArray = load("res://scripts/RenderCapture.gd").file_bytes(info)
		if bytes.size() == 0:
			continue
		var p := _abs("%s/%s.%s" % [WORK, sid, info.ext])
		var f := File.new()
		if f.open(p, File.WRITE) == OK:
			f.store_buffer(bytes)
			f.close()
			paths[sid] = p
	# the short sounds, laid out on a few tracks (one sound at a time each)
	var variants := {} # "sid|pitch|db" -> PoolByteArray (48 kHz stereo 16-bit)
	var lanes := [] # [ [ [start sample, key], ... ], ... ]
	var lane_end := []
	var list: Array = data.sounds.duplicate()
	list.sort_custom(self, "_by_t")
	for s in list:
		if not paths.has(s.sid):
			continue
		var key := "%s|%.3f|%.1f" % [s.sid, float(s.pitch), float(s.db)]
		if not variants.has(key):
			var dec = yield(_decode(paths[s.sid], float(s.pitch), float(s.db)), "completed")
			variants[key] = dec
		var pcm: PoolByteArray = variants[key]
		if pcm.size() == 0:
			continue
		var start := int(round(float(s.t) * RATE)) * 4
		var lane := -1
		for i in lane_end.size():
			if lane_end[i] <= start:
				lane = i
				break
		if lane < 0:
			if lanes.size() >= MAX_LANES:
				continue
			lanes.append([])
			lane_end.append(0)
			lane = lanes.size() - 1
		lanes[lane].append([start, key])
		lane_end[lane] = start + pcm.size()
	var inputs := ["-i", _abs(WORK + "/video.mp4")]
	var labels := []
	var zeros := PoolByteArray()
	zeros.resize(RATE * 4)
	for i in zeros.size():
		zeros[i] = 0
	for li in lanes.size():
		var p := _abs("%s/lane%d.raw" % [WORK, li])
		var f := File.new()
		if f.open(p, File.WRITE) != OK:
			continue
		var at := 0
		for e in lanes[li]:
			var gap: int = e[0] - at
			while gap > 0:
				var n: int = min(gap, zeros.size())
				f.store_buffer(zeros if n == zeros.size() else zeros.subarray(0, n - 1))
				gap -= n
			var pcm: PoolByteArray = variants[e[1]]
			f.store_buffer(pcm)
			at = e[0] + pcm.size()
		f.close()
		inputs += ["-f", "s16le", "-ar", str(RATE), "-ac", "2", "-i", p]
		labels.append("[%d:a]" % (_input_count(inputs) - 1))
	# the music pieces: cut, sped up and placed by ffmpeg
	var filters := []
	var mi := 0
	for m in data.music:
		if not paths.has(m.sid):
			continue
		inputs += ["-i", paths[m.sid]]
		var idx := _input_count(inputs) - 1
		var pitch: float = max(float(m.pitch), 0.05)
		var src_dur: float = (float(m.end) - float(m.t)) * pitch
		var speed := ("asetrate=%d,aresample=%d" % [int(round(RATE * pitch)), RATE])
		if bool(m.keep_pitch) and abs(pitch - 1.0) > 0.001:
			speed = _atempo(pitch)
		filters.append("[%d:a]atrim=start=%.4f:duration=%.4f,asetpts=PTS-STARTPTS,aresample=%d,aformat=channel_layouts=stereo,%s,volume=%.2fdB,adelay=%d:all=1[m%d]" % [
			idx, float(m.from), src_dur, RATE, speed, float(m.db), int(round(float(m.t) * 1000.0)), mi])
		labels.append("[m%d]" % mi)
		mi += 1
	var out_dir := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	if out_dir == "":
		out_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	out_dir += "/Chromia"
	Directory.new().make_dir_recursive(out_dir)
	var vname := _title.replace("·", "-")
	var clean := ""
	for ch in vname:
		clean += "" if (ch in "<>:\"/\\|?*" or ord(ch) < 32) else ch
	clean = clean.strip_edges().replace("  ", " ")
	if clean == "":
		clean = "Chromia video"
	var out := "%s/%s %s.mp4" % [out_dir, clean.substr(0, 80), _stamp()]
	var args := ["-hide_banner", "-loglevel", "error", "-y"] + inputs
	if labels.empty():
		args += ["-map", "0:v", "-c:v", "copy", out]
	else:
		filters.append("%samix=inputs=%d:normalize=0:duration=longest[aout]" % [PoolStringArray(labels).join(""), labels.size()])
		var script := _abs(WORK + "/filter.txt")
		var f := File.new()
		if f.open(script, File.WRITE) == OK:
			f.store_string(PoolStringArray(filters).join(";\n"))
			f.close()
		args += ["-filter_complex_script", script, "-map", "0:v", "-map", "[aout]", "-c:v", "copy",
			"-c:a", "aac", "-b:a", "192k", "-t", "%.3f" % dur, "-movflags", "+faststart", out]
	var r = yield(_ffmpeg_run(args), "completed")
	if int(r[0]) != 0:
		_fail("ffmpeg couldn't put the sound on." + (("\n" + String(r[1]).substr(0, 300)) if String(r[1]) != "" else ""))
		return ""
	return out

func _input_count(inputs: Array) -> int:
	var n := 0
	for a in inputs:
		if String(a) == "-i":
			n += 1
	return n

# a speed with the pitch kept (atempo takes 0.5 - 2 at a time)
func _atempo(speed: float) -> String:
	var parts := []
	var s := speed
	while s > 2.0:
		parts.append("atempo=2.0")
		s /= 2.0
	while s < 0.5:
		parts.append("atempo=0.5")
		s /= 0.5
	parts.append("atempo=%.5f" % s)
	return PoolStringArray(parts).join(",")

# a short sound as 48 kHz stereo 16-bit, at its pitch and volume. Always yields.
func _decode(path: String, pitch: float, db: float):
	var raw := _abs("%s/dec_%d.raw" % [WORK, randi()])
	var af := "aresample=%d,asetrate=%d,aresample=%d,volume=%.2fdB" % [RATE, int(round(RATE * max(pitch, 0.05))), RATE, db]
	var r = yield(_ffmpeg_run(["-hide_banner", "-loglevel", "error", "-y", "-i", path, "-af", af, "-ac", "2", "-ar", str(RATE), "-f", "s16le", "-acodec", "pcm_s16le", raw]), "completed")
	var out := PoolByteArray()
	if int(r[0]) == 0:
		var f := File.new()
		if f.open(raw, File.READ) == OK:
			out = f.get_buffer(f.get_len())
			f.close()
	Directory.new().remove(raw)
	return out

func _by_t(a, b) -> bool:
	return float(a.t) < float(b.t)

func _stamp() -> String:
	var d := OS.get_datetime()
	return "%04d-%02d-%02d %02d.%02d.%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]

func _clean_work():
	var dir := Directory.new()
	if dir.open(WORK) != OK:
		return
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			dir.remove(f)
		f = dir.get_next()
	dir.list_dir_end()

func _fail(why: String):
	busy = false
	Rhythia.rendering = false
	OS.set_window_title(_old_title)
	_end_ffmpeg()
	_clean_work()
	Globals.notify(Globals.NOTIFY_WARN, why, "Save video")
