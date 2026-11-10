extends Node

# Save video (the results after a play, EndInfo.gd): the play made into a
# video on the website, the way you saw it.
#
# The server gets your settings (what a spectator watching you with your
# settings sees: SpectateSettings.collect(); your own pictures, fonts and
# meshes go up by hash first), then the play's replay, and the map when it
# doesn't have it (.sspm only). The browser opens a private page,
# /render/<link> (savia_web website/render.html): the website's game view
# plays it with those settings and records it as an MP4. Works for a part
# of a map too (a fail or a give-up: the replay stops there).

const RENDER_URL := "https://savia.nysr.host/savia-render"
const MAX_MAP_BYTES := 150 * 1024 * 1024

var _replay_file := ""
var _song = null
var _title := ""
var _busy := false

# from the results: the replay of the play just made, its map
static func start(tree: SceneTree, replay_file: String, song, title: String):
	var cur = tree.root.get_node_or_null("VideoExport")
	if cur != null and cur.get("_busy"):
		Globals.notify(Globals.NOTIFY_INFO, "Still sending the last one.", "Save video")
		return
	if cur != null:
		cur.queue_free()
	var n = load("res://scripts/VideoExport.gd").new()
	n.name = "VideoExport"
	n._replay_file = replay_file
	n._song = song
	n._title = title
	tree.root.add_child(n)
	n.call_deferred("_go")

# the replay of the play that just ended ("" when there is none: watching a
# replay, replays not kept, or it couldn't be written)
static func last_replay_file() -> String:
	# a replay just watched (dragged into the game, or opened from a file): that file
	if Rhythia.was_replay:
		var rp := String(Rhythia.last_replay_path)
		return rp if rp.to_lower().ends_with(".sspre") and File.new().file_exists(rp) else ""
	if Rhythia.replay == null or String(Rhythia.replay.id) == "":
		return ""
	var p: String = Globals.p("user://replays/%s.sspre" % Rhythia.replay.id)
	return p if File.new().file_exists(p) else ""

func _auth() -> String:
	return "client_id=%s" % String(Rhythia._ensure_client_id()).http_escape()

# the map's own file, when it's an .sspm the server can play
func _map_file() -> String:
	if _song == null:
		return ""
	var p := String(_song.get("initFile")) if _song.get("initFile") != null else ""
	if p == "" or not p.to_lower().ends_with(".sspm") or not File.new().file_exists(p):
		return ""
	return p

func _go():
	_busy = true
	var lm = get_node_or_null("/root/LobbyManager")
	# your own pictures / fonts / meshes / backgrounds and cursor, by hash
	if lm != null:
		if lm.has_method("upload_spectate_assets"):
			lm.upload_spectate_assets()
		if lm.has_method("upload_cursor_picture"):
			lm.upload_cursor_picture()
	var settings: Dictionary = load("res://scripts/SpectateSettings.gd").collect()
	var map_file := _map_file()
	var body := {
		"settings": settings,
		"song_id": String(_song.id) if _song != null else "",
		"song_name": String(_song.name) if _song != null else "",
		"map_sha": File.new().get_sha256(map_file) if map_file != "" else "",
		"title": _title,
	}
	Globals.notify(Globals.NOTIFY_INFO, "Getting your video ready...", "Save video")
	var r = yield(_request("%s?%s" % [RENDER_URL, _auth()], HTTPClient.METHOD_POST, ["Content-Type: application/json"], JSON.print(body).to_utf8()), "completed")
	if not (r is Dictionary) or not r.get("ok", false):
		return _fail(String(r.get("error", "")) if r is Dictionary else "")
	var token := String(r.get("token", ""))
	if r.get("need_map", false) and map_file == "":
		return _fail("This map isn't on the server and isn't an .sspm file, so the website can't play it.")
	# the page waits for the rest
	OS.shell_open(String(r.get("url", "")))
	var rep := _read(_replay_file)
	if rep.size() == 0:
		return _fail("The replay couldn't be read.")
	var r2 = yield(_request("%s/%s/replay?%s" % [RENDER_URL, token, _auth()], HTTPClient.METHOD_POST, ["Content-Type: application/octet-stream"], rep), "completed")
	if not (r2 is Dictionary) or not r2.get("ok", false):
		return _fail(String(r2.get("error", "")) if r2 is Dictionary else "")
	if r.get("need_map", false):
		var f := File.new()
		if f.open(map_file, File.READ) != OK or f.get_len() > MAX_MAP_BYTES:
			f.close()
			return _fail("The map is too big to send.")
		f.close()
		Globals.notify(Globals.NOTIFY_INFO, "Sending the map...", "Save video")
		var r3 = yield(_request("%s/%s/map?%s" % [RENDER_URL, token, _auth()], HTTPClient.METHOD_POST, ["Content-Type: application/octet-stream"], _read(map_file)), "completed")
		if not (r3 is Dictionary) or not r3.get("ok", false):
			return _fail(String(r3.get("error", "")) if r3 is Dictionary else "")
	Globals.notify(Globals.NOTIFY_SUCCEED, "Opened in your browser: pick Website viewer or Game view there and press Make video.", "Save video")
	_busy = false

func _fail(why: String):
	_busy = false
	Globals.notify(Globals.NOTIFY_WARN, why if why != "" else "Couldn't reach the server.", "Save video")

func _read(path: String) -> PoolByteArray:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var b := f.get_buffer(f.get_len())
	f.close()
	return b

# one request; -> its answer as a Dictionary, or null. Always yields.
func _request(url: String, method: int, headers: Array, data: PoolByteArray):
	yield(get_tree(), "idle_frame")
	var http := HTTPRequest.new()
	http.use_threads = true # (a big map: never on the game's main thread)
	http.timeout = 120
	add_child(http)
	if http.request_raw(url, PoolStringArray(headers), true, method, data) != OK:
		http.queue_free()
		return null
	var res: Array = yield(http, "request_completed")
	http.queue_free()
	var p := JSON.parse((res[3] as PoolByteArray).get_string_from_utf8())
	return p.result if p.error == OK and p.result is Dictionary else null
