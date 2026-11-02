extends Node

# A video the game can't play (.mp4, .mov, .mkv, .avi...) for the Background
# Editor: sent to the Chromia server, which makes it a .webm (savia_web
# src/videoconvert.js), then downloaded and added as a layer.
#
# It lives under the scene tree's root, so it finishes even if the settings are
# closed meanwhile (the layer is then added to the saved layout).
#   convert(path)  -> "progress"(text), "finished"(webm path or "", error text)

signal progress(text)
signal finished(webm_path, error)

const URL := "https://savia.nysr.host/savia-convert-video"
const EXTS := ["mp4", "mov", "m4v", "mkv", "avi", "wmv", "flv", "3gp"]
const MAX_BYTES := 95 * 1024 * 1024
const POLL_S := 2.0
const GIVE_UP_S := 20 * 60.0
const OUT_DIR := "user://caches/bg_convert"

var src_name := ""
var _job := ""
var _waited := 0.0

static func can_convert(path: String) -> bool:
	return EXTS.has(path.get_extension().to_lower())

static func start(path: String) -> Node:
	var c = load("res://scripts/ui/settings/BgVideoConvert.gd").new()
	c.name = "BgVideoConvert"
	Engine.get_main_loop().root.add_child(c, true)
	c.call_deferred("_begin", path)
	return c

func _begin(path: String):
	src_name = path.get_file()
	var f := File.new()
	if f.open(path, File.READ) != OK:
		_done("", "couldn't open " + src_name)
		return
	if f.get_len() > MAX_BYTES:
		f.close()
		_done("", "%s is too big (95 MB at most)" % src_name)
		return
	var data: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	emit_signal("progress", "Sending %s to the server to convert (%d MB)..." % [src_name, int(ceil(data.size() / 1048576.0))])
	var http := _new_http("_on_started")
	var url := "%s?client_id=%s" % [URL, String(Rhythia._ensure_client_id()).http_escape()]
	if http.request_raw(url, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, data) != OK:
		_done("", "couldn't reach the server")

# one request each (freed when it answers)
func _new_http(method: String, binds: Array = []) -> HTTPRequest:
	var http := HTTPRequest.new()
	http.use_threads = true # (big files: never on the game's main thread)
	add_child(http)
	http.connect("request_completed", self, method, binds)
	http.connect("request_completed", self, "_free_http", [http])
	return http

func _free_http(_r, _c, _h, _b, http: HTTPRequest):
	http.queue_free()

func _json(body: PoolByteArray):
	var r = JSON.parse(body.get_string_from_utf8())
	return r.result if r.error == OK and r.result is Dictionary else {}

func _on_started(result, code, _headers, body):
	var j = _json(body)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_done("", "the server didn't answer (%s)" % (str(code) if code else "no connection"))
		return
	if not j.get("ok", false):
		_done("", Globals.s(j.get("error", "the server refused it")))
		return
	_job = Globals.s(j.get("job", ""))
	emit_signal("progress", "Converting %s on the server..." % src_name)
	_poll_later()

func _poll_later():
	yield(get_tree().create_timer(POLL_S), "timeout")
	_waited += POLL_S
	if _waited > GIVE_UP_S:
		_done("", "converting %s took too long" % src_name)
		return
	if _new_http("_on_status").request("%s/%s" % [URL, _job]) != OK:
		_done("", "couldn't reach the server")

func _on_status(result, code, _headers, body):
	var j = _json(body)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not j.get("ok", false):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_done("", Globals.s(j.get("error", "the server lost the video")))
		else:
			_poll_later() # (a dropped poll: ask again)
		return
	var state := Globals.s(j.get("state", ""))
	if state == "failed":
		_done("", Globals.s(j.get("error", "it couldn't be converted")))
	elif state == "done":
		_download()
	else:
		emit_signal("progress", "Converting %s on the server... (%ds)" % [src_name, int(_waited)])
		_poll_later()

func _download():
	emit_signal("progress", "Downloading the converted %s..." % src_name)
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(OUT_DIR))
	var base := src_name.get_basename()
	var out: String = Globals.p(OUT_DIR).plus_file("%s.webm" % (base if base != "" else "video"))
	var http := _new_http("_on_downloaded", [out])
	http.download_file = out
	if http.request("%s/%s.webm" % [URL, _job]) != OK:
		_done("", "couldn't reach the server")

func _on_downloaded(result, code, _headers, _body, out: String):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		Directory.new().remove(out)
		_done("", "couldn't download the converted video (%s)" % str(code))
		return
	_done(out, "")

func _done(webm: String, error: String):
	if not get_signal_connection_list("finished").empty():
		emit_signal("finished", webm, error)
	else:
		_add_to_saved(webm, error) # (the Background Editor was closed meanwhile)
	queue_free()

# no Background Editor open: the video goes on top of the saved layout
func _add_to_saved(webm: String, error: String):
	if webm == "":
		Globals.notify(Globals.NOTIFY_INFO, "%s: %s" % [src_name, error], "Background Editor")
		return
	var BG = load("res://scripts/BgLayers.gd")
	var d: Dictionary = BG.load_own_data()
	var file: String = BG.import_file(webm) if d.layers.size() < BG.MAX_LAYERS else ""
	Directory.new().remove(webm)
	if file == "":
		Globals.notify(Globals.NOTIFY_INFO, "%s couldn't be added (layer limit or disk)" % src_name, "Background Editor")
		return
	var l: Dictionary = BG.new_layer(file, 16.0 / 9.0)
	l.name = src_name
	d.layers.append(l)
	BG.save_data(d)
	Globals.notify(Globals.NOTIFY_INFO, "%s was converted and added to your background" % src_name, "Background Editor")
