extends Node

# The menu songs, from the Chromia server instead of inside every download
# (they were 15 MB of it): savia_web website/menu-music/ has the songs and
# list.json (file, size, sha256). The first time, they're downloaded one at a
# time into user://caches/menu_music/; after that they play from there, also
# offline. Savia.next_menu_track() plays whichever are here.
#
# One of it under the scene tree's root (start()), so a download carries on
# while songs are played and the menu comes and goes.
#   "track_ready"(path)  a song finished downloading (the menu starts playing
#                        if it was waiting for one)

signal track_ready(path)

const BASE := "https://savia.nysr.host/menu-music/"
const CACHE := "user://caches/menu_music"
const MAX_BYTES := 16 * 1024 * 1024

var songs := [] # [{file, size, sha256}] from list.json (or the cache's copy)
var _queue := []
var _busy := false

static func get_or_start() -> Node:
	var root = Engine.get_main_loop().root
	var n = root.get_node_or_null("MenuMusic")
	if n == null:
		n = load("res://scripts/MenuMusic.gd").new()
		n.name = "MenuMusic"
		root.call_deferred("add_child", n)
	return n

static func cache_dir() -> String:
	return Globals.p(CACHE)

func _ready():
	Directory.new().make_dir_recursive(cache_dir())
	_load_saved_list()
	_fetch_list()

# the songs here now (in the list's order)
func ready_paths() -> Array:
	var out := []
	var f := File.new()
	for s in songs:
		var p := cache_dir().plus_file(String(s.file))
		if f.file_exists(p) and _size(p) == int(s.size):
			out.append(p)
	return out

static func _size(p: String) -> int:
	var f := File.new()
	if f.open(p, File.READ) != OK:
		return -1
	var n := f.get_len()
	f.close()
	return n

static func _clean(v) -> Array:
	var out := []
	if not (v is Dictionary) or not (v.get("songs") is Array):
		return out
	for s in v.songs:
		if not (s is Dictionary):
			continue
		var file := String(s.get("file", ""))
		var size := int(s.get("size", 0))
		var sha := String(s.get("sha256", "")).to_lower()
		# (a plain .ogg name only: it's a file name in the cache)
		if file.get_extension().to_lower() == "ogg" and file == file.get_file() and file.is_valid_filename() and size > 0 and size <= MAX_BYTES and sha.length() == 64:
			out.append({"file": file, "size": size, "sha256": sha})
	return out

func _load_saved_list():
	var f := File.new()
	if f.open(cache_dir().plus_file("list.json"), File.READ) != OK:
		return
	var r := JSON.parse(f.get_as_text())
	f.close()
	if r.error == OK:
		songs = _clean(r.result)

func _fetch_list():
	var http := HTTPRequest.new()
	http.timeout = 20
	add_child(http)
	http.connect("request_completed", self, "_on_list", [http])
	# (?d: a new list at most a day late, whatever caches it on the way)
	if http.request(BASE + "list.json?d=%d" % int(OS.get_unix_time() / 86400)) != OK:
		http.queue_free()
		_retry_later()

# no connection yet (offline, server restarting): asked again later
const RETRY_S := [15, 60, 300]
var _tries := 0

func _retry_later():
	var wait: int = RETRY_S[min(_tries, RETRY_S.size() - 1)]
	_tries += 1
	yield(get_tree().create_timer(wait), "timeout")
	_fetch_list()

func _on_list(result, code, _h, body: PoolByteArray, http: HTTPRequest):
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		Rhythia.trail("menu music: list not reached (%s), %d songs here" % [str(code), ready_paths().size()])
		_retry_later()
		return
	var r := JSON.parse(body.get_string_from_utf8())
	var got := _clean(r.result) if r.error == OK else []
	if got.empty():
		return
	songs = got
	var f := File.new()
	if f.open(cache_dir().plus_file("list.json"), File.WRITE) == OK:
		f.store_string(JSON.print({"v": 1, "songs": songs}))
		f.close()
	_tidy()
	_queue.clear()
	for s in songs:
		var p := cache_dir().plus_file(String(s.file))
		if _size(p) != int(s.size):
			_queue.append(s)
	# (a random one first: the menu has music sooner, and not always the same)
	randomize()
	_queue.shuffle()
	_next()

# songs no longer in the list go
func _tidy():
	var keep := {"list.json": true}
	for s in songs:
		keep[String(s.file)] = true
	var d := Directory.new()
	if d.open(cache_dir()) != OK:
		return
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and not keep.has(n):
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()

func _next():
	if _busy or _queue.empty():
		return
	var s: Dictionary = _queue.pop_front()
	_busy = true
	var part := cache_dir().plus_file(String(s.file) + ".part")
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 120
	http.download_file = part
	http.body_size_limit = MAX_BYTES
	add_child(http)
	http.connect("request_completed", self, "_on_song", [http, s, part])
	if http.request(BASE + String(s.file)) != OK:
		http.queue_free()
		_busy = false

func _on_song(result, code, _h, _b, http: HTTPRequest, s: Dictionary, part: String):
	http.queue_free()
	_busy = false
	var d := Directory.new()
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200 and _size(part) == int(s.size) and File.new().get_sha256(part) == String(s.sha256)
	if ok:
		var p := cache_dir().plus_file(String(s.file))
		d.remove(p)
		ok = d.rename(part, p) == OK
		if ok:
			emit_signal("track_ready", p)
	if not ok:
		d.remove(part)
		Rhythia.trail("menu music: %s didn't download (%s)" % [String(s.file), str(code)])
		if result != HTTPRequest.RESULT_SUCCESS and _queue.empty():
			_retry_later() # (the connection went: the list again, then what's missing)
	_next()
