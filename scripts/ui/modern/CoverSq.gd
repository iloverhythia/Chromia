extends Reference

# Square map covers for the Modern UI's grid (ModernUI.gd): each cover is
# cropped to a square and shrunk to SIZE once, kept in user://caches/covers_sq
# and loaded from there after that. Covers are decoded on a background thread
# (one map at a time, the ones on screen first); get() returns null until a
# cover is ready and "ready(song)" is sent when it is.

signal ready(song)

const DIR := "user://caches/covers_sq"
const SIZE := 256
const MAX_TEX := 160 # covers kept in memory

var _tex := {} # key -> ImageTexture
var _order := [] # keys, oldest first
var _want := [] # songs to make, newest first
var _done := [] # [song, Image] made on the thread
var _mutex := Mutex.new()
var _thread: Thread = null
var _busy := false

static func get_cache():
	var root = Engine.get_main_loop().root
	if not root.has_meta("cover_sq"):
		root.set_meta("cover_sq", load("res://scripts/ui/modern/CoverSq.gd").new())
	return root.get_meta("cover_sq")

static func key_of(song) -> String:
	return ("%s|%s|%s" % [String(song.filePath), String(song.get("cover_offset")), String(song.get("cover_length"))]).md5_text()

func tex_for(song) -> Texture:
	if song == null or not song.has_cover:
		return null
	var k := key_of(song)
	if _tex.has(k):
		_order.erase(k)
		_order.append(k)
		return _tex[k]
	var path: String = Globals.p(DIR).plus_file(k + ".png")
	if File.new().file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return _keep(k, img)
	_mutex.lock()
	if not _want.has(song):
		_want.push_front(song)
		if _want.size() > 64:
			_want.resize(64)
	_mutex.unlock()
	_kick()
	return null

func _keep(k: String, img: Image) -> Texture:
	var t := ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	_tex[k] = t
	_order.append(k)
	while _order.size() > MAX_TEX:
		_tex.erase(_order.pop_front())
	return t

var _dir_made := false
func _kick():
	if _busy:
		return
	if not _dir_made:
		Directory.new().make_dir_recursive(Globals.p(DIR))
		_dir_made = true
	_busy = true
	if OS.can_use_threads():
		if _thread != null and _thread.is_active():
			_thread.wait_to_finish()
		_thread = Thread.new()
		_thread.start(self, "_work")
	else:
		Engine.get_main_loop().connect("idle_frame", self, "_work_one", [], CONNECT_ONESHOT)

static func _square(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		var raw: Image = img.duplicate()
		if img.decompress() != OK or img.is_compressed():
			img = load("res://scripts/content/DxtDecode.gd").decode(raw)
			if img == null:
				return null
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var s: int = min(w, h)
	img = img.get_rect(Rect2((w - s) / 2, (h - s) / 2, s, s))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	return img

func _next_song():
	_mutex.lock()
	var s = _want.pop_front() if not _want.empty() else null
	_mutex.unlock()
	return s

func _work(_u = null):
	while true:
		var song = _next_song()
		if song == null:
			break
		var img = _square(song._decode_cover_pixels())
		if img != null:
			img.save_png(Globals.p(DIR).plus_file(key_of(song) + ".png"))
			_mutex.lock()
			_done.append([song, img])
			_mutex.unlock()
	call_deferred("_finished")

func _work_one():
	var song = _next_song()
	if song != null:
		var img = _square(song._decode_cover_pixels())
		if img != null:
			img.save_png(Globals.p(DIR).plus_file(key_of(song) + ".png"))
			_done.append([song, img])
	_finished()

func _finished():
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null
	_busy = false
	_mutex.lock()
	var done := _done
	_done = []
	var more := not _want.empty()
	_mutex.unlock()
	for d in done:
		_keep(key_of(d[0]), d[1])
		emit_signal("ready", d[0])
	if more:
		_kick()
