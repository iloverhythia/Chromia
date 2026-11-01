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
		if not (out.has("replay") and out.has("player") and out.has("map")):
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
var _third: Button
var third_person := false

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
	# 3rd person: the alternate replay camera with the avatar (3 switches it while it plays too)
	_third = _button("3rd person: off", "_on_third")
	_third.hint_tooltip = "Watch from behind, with an avatar playing (press 3 while it plays to switch)"
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

# ── playing ──
func _on_third():
	third_person = not third_person
	_third.text = "3rd person: on" if third_person else "3rd person: off"

func _on_watch():
	recording = false
	_play()

func _on_record():
	recording = true
	# a big picture while it records, not the size of the game view on the page
	_record_size(true)
	_buttons.visible = false
	yield(get_tree().create_timer(0.8), "timeout")
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
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.alt_cam = third_person
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
			var js = Engine.get_singleton("JavaScript")
			if js != null:
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

func _stop_recording():
	if not recording:
		return
	recording = false
	var js = Engine.get_singleton("JavaScript")
	if js != null:
		js.eval("window.__chromiaRec && window.__chromiaRec.stop(%s)" % to_json(title), true)
	_status.text = "Your video is ready: Save video, under the game."
	_record_size(false)
