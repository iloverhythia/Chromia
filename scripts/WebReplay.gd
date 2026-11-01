extends Node

# The browser version opened as the website's "Game view" of a replay:
#   /play/index.html?replay=1&player=<number>&map=<map>&i=<pass>
# (the Savia server hosts the browser build at /play: src/webgame.js). It
# downloads the map and the replay from that same site and plays the replay
# with the game itself; back in the menu it offers to watch it again.
# While it's on, the game stays offline (no account for every watcher) and
# skips the first-start questions.

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
	var w = tree.root.get_node_or_null("WebReplay")
	if w == null:
		w = load("res://scripts/WebReplay.gd").new()
		w.name = "WebReplay"
		tree.root.call_deferred("add_child", w)
	else:
		w.call_deferred("_again")

var origin := ""
var replay_path := ""
var title := ""
var _busy := false

func _ready():
	var js = Engine.get_singleton("JavaScript")
	origin = String(js.eval("location.origin", true)) if js != null else ""
	call_deferred("_run")

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

func _fail(text: String):
	_busy = false
	Globals.confirm_prompt.open(text, "Replay", [{text = "OK", wait = 0}])
	yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()

func _save(path: String, bytes: PoolByteArray) -> bool:
	Directory.new().make_dir_recursive(Globals.p(path).get_base_dir())
	var f := File.new()
	if f.open(Globals.p(path), File.WRITE) != OK:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

func _run():
	if _busy:
		return
	_busy = true
	var p := params()
	Globals.notify(Globals.NOTIFY_INFO, "Getting the replay...", "Replay")
	var info = _json(yield(_fetch("/savia-public/api/map/" + String(p.map).http_escape()), "completed"))
	if not (info is Dictionary) or String(info.get("slug", "")) == "":
		return _fail("This map isn't on the server, so its replay can't be shown.")
	var slug := String(info.slug)
	var map_bytes = yield(_fetch("/ranked-maps/%s.sspm" % slug.http_escape()), "completed")
	if map_bytes == null:
		return _fail("The map couldn't be downloaded.")
	var map_path := "user://maps/web_%s.sspm" % slug
	if not _save(map_path, map_bytes):
		return _fail("The map couldn't be saved in the browser.")
	if Rhythia.registry_song:
		Rhythia.registry_song.add_sspm_map(Globals.p(map_path))
	var rep = yield(_fetch("/savia-public/api/player/%s/replay/%s/%s" % [String(p.player).http_escape(), String(p.map).http_escape(), String(p.get("i", "0")).http_escape()]), "completed")
	if rep == null:
		return _fail("This pass has no replay.")
	replay_path = "user://web_replay.sspre"
	if not _save(replay_path, rep):
		return _fail("The replay couldn't be saved in the browser.")
	var who = _json(yield(_fetch("/savia-public/api/player/" + String(p.player).http_escape()), "completed"))
	title = "%s on %s" % [String(who.get("name", "Player")) if who is Dictionary else "A player", String(info.get("song_name", slug))]
	# (a click before playing: browsers only let a page make sound after one)
	Globals.confirm_prompt.open("Watch %s?" % title, "Replay", [{text = "Watch", wait = 0}])
	yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	_play()

func _again():
	if _busy or replay_path == "":
		return
	_busy = true
	Globals.confirm_prompt.open("Watch %s again?" % title, "Replay", [{text = "Watch again", wait = 0}])
	yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	_play()

func _play():
	_busy = false
	Rhythia.replay = Replay.new()
	Rhythia.replaying = true
	Rhythia.replay_path = Globals.p(replay_path)
	get_tree().change_scene("res://scenes/loaders/songload.tscn")
