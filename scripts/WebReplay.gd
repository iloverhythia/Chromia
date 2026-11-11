extends Node

# The browser version opened as the website's "Game view" of a replay:
#   /play/index.html?replay=1&player=<number>&map=<map>&i=<pass>
# (the Savia server hosts the browser build at /play: src/webgame.js). Only
# the replay shows: a black screen of its own covers the menu (no intro, no
# menu music) with Watch and Record video; the map and the replay come from
# the same site, and the game's replay player plays it. Record video saves it
# as a video file (MP4 where the browser can): the page's recorder, which the
# server adds to the browser build's page (window.__chromiaRec), takes the
# game's picture and sound while the replay plays.
# While it's on, the game stays offline (no account for every watcher).

const META := "web_replay_params"

static func params() -> Dictionary:
	if Engine.has_meta(META):
		return Engine.get_meta(META)
	var out := {}
	if OS.has_feature("JavaScript"):
		var js = Engine.get_singleton("JavaScript")
		var q := String(js.eval("location.search", true)) if js != null else ""
		for part in q.trim_prefix("?").split("&", false):
			var kv: PoolStringArray = part.split("=", true, 1)
			out[kv[0].percent_decode()] = kv[1].replace("+", " ").percent_decode() if kv.size() > 1 else ""
		# (or a private video link: ?render=<link>, made by the game's Save video)
		if not (out.has("replay") and out.has("player") and out.has("map")) and not out.has("render"):
			out = {}
	Engine.set_meta(META, out)
	return out

static func wanted() -> bool:
	return not params().empty()

# menu2.gd, every time the menu opens
static func menu_opened(tree: SceneTree):
	if not wanted():
		return
	if tree.root.get_node_or_null("WebReplay") == null:
		var w = load("res://scripts/WebReplay.gd").new()
		w.name = "WebReplay"
		tree.root.call_deferred("add_child", w)

var origin := ""
var replay_path := ""
var title := ""
var ready_to_play := false
var recording := false
var _game_scene = null # the song scene while the replay plays
var _waiting := false # Watch / Record pressed, the song not started yet
var _seen_loader := false
var _ending := false # the song ended, the video stops in a moment

var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _status: Label
var _buttons: HBoxContainer
var _watch: Button
var _record: Button

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	var js = Engine.get_singleton("JavaScript")
	origin = String(js.eval("location.origin", true)) if js != null else ""
	_build_screen()
	call_deferred("_run")

# ── the screen covering the menu ──
func _build_screen():
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.margin_left = -320
	box.margin_right = 320
	box.margin_top = -90
	box.margin_bottom = 90
	box.alignment = BoxContainer.ALIGN_CENTER
	box.add_constant_override("separation", 14)
	bg.add_child(box)
	_title = _label(box, "", 30, Color(1, 1, 1))
	_sub = _label(box, "", 18, Color(0.65, 0.66, 0.7))
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGN_CENTER
	_buttons.add_constant_override("separation", 12)
	_buttons.visible = false
	box.add_child(_buttons)
	_watch = _button("Watch", "_on_watch")
	_record = _button("Record video", "_on_record")
	_record.visible = _can_record()
	# a video link: the game runs one frame at a time there (--fixed-fps,
	# webgame.js), so just watching would play at the screen's speed
	if params().has("render"):
		_watch.visible = false
		_record.text = "Make video"
	_status = _label(box, "Getting the replay...", 15, Color(0.55, 0.56, 0.6))

func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.align = Label.ALIGN_CENTER
	l.autowrap = true
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = size
	l.add_font_override("font", f)
	l.add_color_override("font_color", color)
	parent.add_child(l)
	return l

func _button(text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.rect_min_size = Vector2(170, 46)
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = 18
	b.add_font_override("font", f)
	b.connect("pressed", self, method)
	_buttons.add_child(b)
	return b

func _can_record() -> bool:
	var js = Engine.get_singleton("JavaScript")
	return js != null and bool(js.eval("!!(window.__chromiaRec && window.__chromiaRec.can())", true))

# ── getting the map and the replay ──
# GET a path on the site -> its bytes (null when it fails). Always yields.
func _fetch(path: String):
	yield(get_tree(), "idle_frame")
	var r := HTTPRequest.new()
	r.download_chunk_size = 262144
	add_child(r)
	if r.request(origin + path) != OK:
		r.queue_free()
		return null
	var res: Array = yield(r, "request_completed")
	r.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return null
	return res[3]

func _json(bytes):
	if bytes == null:
		return null
	var p := JSON.parse((bytes as PoolByteArray).get_string_from_utf8())
	return p.result if p.error == OK else null

func _save(path: String, bytes: PoolByteArray) -> bool:
	Directory.new().make_dir_recursive(Globals.p(path).get_base_dir())
	var f := File.new()
	if f.open(Globals.p(path), File.WRITE) != OK:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

func _fail(text: String):
	_status.text = text

func _run():
	var p := params()
	if p.has("render"):
		_run_render(String(p.render))
		return
	var info = _json(yield(_fetch("/savia-public/api/map/" + String(p.map).http_escape()), "completed"))
	if not (info is Dictionary) or String(info.get("slug", "")) == "":
		return _fail("This map isn't on the server, so its replay can't be shown.")
	var slug := String(info.slug)
	_title.text = String(info.get("song_name", slug))
	var who = _json(yield(_fetch("/savia-public/api/player/" + String(p.player).http_escape()), "completed"))
	var name := String(who.get("name", "a player")) if who is Dictionary else "a player"
	_sub.text = "played by %s" % name
	title = "%s on %s" % [name, _title.text]
	var map_bytes = yield(_fetch("/ranked-maps/%s.sspm" % slug.http_escape()), "completed")
	if map_bytes == null:
		return _fail("The map couldn't be downloaded.")
	var map_path := "user://maps/web_%s.sspm" % slug
	if not _save(map_path, map_bytes):
		return _fail("The map couldn't be saved in the browser.")
	# the downloaded map, in place of any entry with its id (the browser
	# version lists online maps whose notes aren't downloaded: "no notes"),
	# and the one the replay plays whatever id the player had (Replay.gd)
	var song = Song.new()
	var res = song.load_from_sspm(Globals.p(map_path))
	if res is String:
		return _fail("The map couldn't be read (%s)." % res)
	if Rhythia.registry_song:
		Rhythia.registry_song.check_and_remove_id(song.id)
		Rhythia.registry_song.add_item(song)
	Engine.set_meta("web_replay_song", song)
	var rep = yield(_fetch("/savia-public/api/player/%s/replay/%s/%s" % [String(p.player).http_escape(), String(p.map).http_escape(), String(p.get("i", "0")).http_escape()]), "completed")
	if rep == null:
		return _fail("This pass has no replay.")
	replay_path = "user://web_replay.sspre"
	if not _save(replay_path, rep):
		return _fail("The replay couldn't be saved in the browser.")
	ready_to_play = true
	_status.text = ""
	_buttons.visible = true

# ── a private video (the game's Save video: VideoExport.gd) ──
# The map, the replay and the player's settings come from the link; their
# settings are put on (SpectateSettings.apply, as when watching someone with
# theirs) before it plays, with their own pictures downloaded first.
func _run_render(t: String):
	if t.length() != 32 or not t.is_valid_hex_number():
		return _fail("This video link isn't right.")
	var info = _json(yield(_fetch("/savia-render/%s" % t), "completed"))
	if not (info is Dictionary) or not bool(info.get("ok", false)):
		return _fail("This video link has expired.")
	_title.text = String(info.get("song_name", "")) if String(info.get("song_name", "")) != "" else "Your play"
	var who = info.get("player")
	var name := String(who.get("name", "")) if who is Dictionary else ""
	_sub.text = ("played by %s" % name) if name != "" else ""
	title = "%s - %s" % [name if name != "" else "Chromia", _title.text]
	_status.text = "Getting the map..."
	var map_bytes = yield(_fetch("/savia-render/%s/map" % t), "completed")
	if map_bytes == null:
		return _fail("The map couldn't be downloaded.")
	var map_path := "user://maps/web_render.sspm"
	if not _save(map_path, map_bytes):
		return _fail("The map couldn't be saved in the browser.")
	var song = Song.new()
	var res = song.load_from_sspm(Globals.p(map_path))
	if res is String:
		return _fail("The map couldn't be read (%s)." % res)
	if Rhythia.registry_song:
		Rhythia.registry_song.check_and_remove_id(song.id)
		Rhythia.registry_song.add_item(song)
	Engine.set_meta("web_replay_song", song)
	var rep = yield(_fetch("/savia-render/%s/replay" % t), "completed")
	if rep == null:
		return _fail("The replay couldn't be downloaded.")
	replay_path = "user://web_replay.sspre"
	if not _save(replay_path, rep):
		return _fail("The replay couldn't be saved in the browser.")
	_status.text = "Putting on their settings..."
	var settings = _json(yield(_fetch("/savia-render/%s/settings" % t), "completed"))
	if settings is Dictionary and not settings.empty():
		yield(_apply_settings(settings), "completed")
	ready_to_play = true
	_status.text = ""
	_buttons.visible = true

func _apply_settings(s: Dictionary):
	yield(get_tree(), "idle_frame")
	# their border, note mesh, font and backgrounds (this site has them: the
	# game sends them when it makes the video, as for spectators)
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null and lm.has_method("fetch_spectate_assets"):
		lm.fetch_spectate_assets(s)
		var waited := 0.0
		while waited < 12.0 and lm.has_method("spectate_assets_ready") and not lm.spectate_assets_ready():
			yield(get_tree().create_timer(0.25), "timeout")
			waited += 0.25
	# their cursor picture (the game's own when they have none); this browser's
	# game (only used for these videos) takes it as its own
	for ext in ["png", "jpg", "jpeg", "webp", "gif"]:
		Directory.new().remove(Globals.p("user://cursor." + ext))
	var sha := String(s.get("cursor_image", "")).to_lower()
	if sha.length() == 64 and sha.is_valid_hex_number():
		var pic = yield(_fetch("/savia-cursor/%s.png" % sha), "completed")
		if pic != null:
			_save("user://cursor.png", pic)
	_render_settings = s

# Their settings, put on just before each play (the menu clears their
# backgrounds and font when it opens), as this browser game's own: put on as
# "someone else's" (SpectateSettings' backup), the song's load would put
# "yours" back, so the backup is dropped
var _render_settings := {}
func _put_render_settings():
	if _render_settings.empty():
		return
	var spec = load("res://scripts/SpectateSettings.gd")
	spec.apply(_render_settings, -1)
	for k in ["spec_backup", "spec_for"]:
		if Rhythia.has_meta(k):
			Rhythia.remove_meta(k)
	Directory.new().remove(Globals.p(spec.BACKUP_FILE))

# ── playing ──
func _on_watch():
	recording = false
	_play()

func _on_record():
	recording = true
	# a big picture while it records, not the size of the game view on the page
	_record_size(true)
	_buttons.visible = false
	yield(get_tree().create_timer(0.8), "timeout")
	# a video link, where the browser can: made one frame at a time (smooth
	# however slow the browser is), else recorded as it plays
	_frames = false
	var js = Engine.get_singleton("JavaScript")
	# (a server with fcan also starts video links with --fixed-fps)
	if js != null and params().has("render") and bool(js.eval("!!(window.__chromiaRec && window.__chromiaRec.fcan && window.__chromiaRec.fcan())", true)):
		_status.text = "Getting the video maker ready..."
		# (the rate the page started the game at: 60, or 120 on an owner's link, webgame.js)
		_fps = int(js.eval("window.__chromiaRenderFps || 60", true))
		if _fps != 120:
			_fps = 60
		js.eval("window.__chromiaRec.fbegin(%d)" % _fps, true)
		var waited := 0.0
		while waited < 10.0 and int(js.eval("window.__chromiaRec.fready()", true)) == 0:
			yield(get_tree().create_timer(0.1), "timeout")
			waited += 0.1
		_frames = int(js.eval("window.__chromiaRec.fready()", true)) == 1
		_status.text = ""
	_play()

# The recording's size, on / off. In the score page (a frame): the page draws
# the frame at 1920x1080 and shrinks it to fit, so the video is 1080p.
# Fullscreen needed a click the browser could see, and the game reads clicks
# a frame later, so it was refused. On its own page: fullscreen, when allowed.
func _record_size(on: bool):
	var js = Engine.get_singleton("JavaScript")
	if js == null:
		return
	var inside := "window.parent && window.parent !== window"
	js.eval("try { if (%s) window.parent.postMessage({ chromia: 'record-size', on: %s }, location.origin); } catch (e) {}" % [inside, "true" if on else "false"], true)
	if on:
		js.eval("try { if (!(%s)) { var d = document.documentElement; (d.requestFullscreen || d.webkitRequestFullscreen).call(d); } } catch (e) {}" % inside, true)
	else:
		js.eval("try { if (document.fullscreenElement) document.exitFullscreen(); } catch (e) {}", true)

func _play():
	if not ready_to_play:
		return
	_buttons.visible = false
	_status.text = "Starting..."
	_game_scene = null
	_waiting = true
	_seen_loader = false
	_ending = false
	_put_render_settings() # (a private video: the player's settings)
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = Globals.p(replay_path)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

# the screen hides while the song plays, and comes back (Watch again) after
func _process(_delta):
	var cur = get_tree().current_scene
	if cur == null or not ready_to_play:
		return
	var file := String(cur.filename).to_lower()
	if _waiting:
		# Watch / Record pressed: the song loader, then the song
		if file.find("songload") != -1:
			_seen_loader = true
			return
		if not _seen_loader:
			return
		_waiting = false
		_game_scene = cur
		_layer.visible = false
		if recording:
			_show_logo(true)
			var js = Engine.get_singleton("JavaScript")
			if _frames:
				_cap = load("res://scripts/RenderCapture.gd").new()
				add_child(_cap)
				_cap.connect("frame_drawn", self, "_on_frame_drawn")
				_cap.begin(_fps, true)
			elif js != null:
				js.eval("window.__chromiaRec && window.__chromiaRec.start(60)", true)
	elif _game_scene != null and cur == _game_scene and not _ending:
		# the song ended (Game.ending): a moment more, then the video stops and
		# it's back here, without the results screen
		var g = cur.get_node_or_null("Game")
		if g != null and bool(g.get("ending")):
			_ending = true
			yield(get_tree().create_timer(1.2), "timeout")
			_stop_recording()
			if get_tree().current_scene == _game_scene:
				get_tree().change_scene("res://scenes/loaders/menuload.tscn")
	elif _game_scene != null and cur != _game_scene:
		# the song is over (back to the menu)
		_game_scene = null
		_ending = false
		_stop_recording()
		_watch.text = "Watch again"
		_buttons.visible = true
		_layer.visible = true

# The Chromia mark in the bottom right corner of every video (not while just watching)
var _logo_layer: CanvasLayer = null
func _show_logo(on: bool):
	if not on:
		if _logo_layer != null and is_instance_valid(_logo_layer):
			_logo_layer.queue_free()
		_logo_layer = null
		return
	if _logo_layer != null and is_instance_valid(_logo_layer):
		return
	_logo_layer = CanvasLayer.new()
	_logo_layer.layer = 125 # (over the song, under this screen)
	add_child(_logo_layer)
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
	_logo_layer.add_child(logo)

func _stop_recording():
	_show_logo(false)
	if not recording:
		return
	recording = false
	var js = Engine.get_singleton("JavaScript")
	if _cap != null:
		_finish_frames(js)
		_record_size(false)
		return
	if js != null:
		js.eval("window.__chromiaRec && window.__chromiaRec.stop(%s)" % to_json(title), true)
	_status.text = "Your video is ready: Save video, under the game."
	_record_size(false)

# ── one frame at a time (RenderCapture.gd and the page's fframe / ffinish) ──
var _frames := false
var _fps := 60
var _cap = null

func _on_frame_drawn(i: int):
	var js = Engine.get_singleton("JavaScript")
	if js != null:
		js.eval("window.__chromiaRec.fframe(%d)" % i, true)

# the frames are in: the sounds' files and what played when go to the page,
# which mixes the sound and finishes the MP4
func _finish_frames(js):
	var data: Dictionary = _cap.end()
	_cap.queue_free()
	_cap = null
	if js == null:
		return
	for sid in data.files.keys():
		var bytes: PoolByteArray = load("res://scripts/RenderCapture.gd").file_bytes(data.files[sid])
		if bytes.size() > 0:
			js.eval("window.__chromiaRec.fsound(%s, '%s')" % [to_json(String(sid)), Marshalls.raw_to_base64(bytes)], true)
	var spec := { "frames": data.frames, "fps": data.fps, "music": data.music, "sounds": data.sounds }
	js.eval("window.__chromiaRec.ffinish(%s, %s)" % [to_json(spec), to_json(title)], true)
	# the page says how it's going
	while true:
		var st := String(js.eval("window.__chromiaRec.fstate()", true))
		_status.text = st
		if st.begins_with("Your video is ready") or st.begins_with("Something went wrong"):
			break
		yield(get_tree().create_timer(0.5), "timeout")
