extends Reference

# Square map covers: the grid map list (MapGrid.gd), the lobby map picker
# (LobbyMapPicker.gd) and the Modern UI (ModernUI.gd). Each cover is cropped
# to a square and shrunk to SIZE once, kept in user://caches/covers_sq160 and
# loaded from there after that. tex_for() never touches the disk: it returns
# a cover already in memory, or null and asks for it; "ready(song)" is sent
# when it's there.
#
# Fast on every device (big libraries, VR / Quest):
#  - reading the kept file, or making it from the map, happens on background
#    threads (a few at once), the covers asked for last first;
#  - mipmaps are made on those threads too; the main thread only turns a few
#    finished pictures into textures each frame (no hitch when a screenful
#    arrives at once);
#  - covers made before at 256 px (covers_sq) are shrunk from that file
#    instead of being decoded from the map again.

signal ready(song)

const DIR := "user://caches/covers_sq160"
const OLD_DIR := "user://caches/covers_sq" # (256 px, before)
const SIZE := 160
const MAX_TEX := 480 # covers kept in memory
const MAX_WANT := 160 # asked for and not made yet (older ones are dropped)
const PER_FRAME := 8 # textures made per frame on the main thread

var _tex := {} # key -> ImageTexture
var _order := [] # keys, oldest first
var _want := [] # songs to make, newest first
var _asked := {} # key -> true (in _want or being made)
var _done := [] # [song, key, Image] made on a thread
var _mutex := Mutex.new()
var _threads := []
var _running := 0

static func get_cache():
	var root = Engine.get_main_loop().root
	if not root.has_meta("cover_sq"):
		root.set_meta("cover_sq", load("res://scripts/ui/modern/CoverSq.gd").new())
	return root.get_meta("cover_sq")

static func key_of(song) -> String:
	return ("%s|%s|%s" % [String(song.filePath), String(song.get("cover_offset")), String(song.get("cover_length"))]).md5_text()

static func _max_threads() -> int:
	if not OS.can_use_threads():
		return 0
	return int(clamp(OS.get_processor_count() / 2, 1, 3))

func tex_for(song) -> Texture:
	if song == null or not song.has_cover:
		return null
	var k := key_of(song)
	if _tex.has(k):
		_order.erase(k)
		_order.append(k)
		return _tex[k]
	_mutex.lock()
	if _asked.has(k):
		# (asked again: to the front)
		var i := _want.find(song)
		if i > 0:
			_want.remove(i)
			_want.push_front(song)
	else:
		_asked[k] = true
		_want.push_front(song)
		while _want.size() > MAX_WANT:
			var old = _want.pop_back()
			_asked.erase(key_of(old))
	_mutex.unlock()
	_kick()
	return null

var _dir_made := false
func _kick():
	if not _dir_made:
		Directory.new().make_dir_recursive(Globals.p(DIR))
		_dir_made = true
	var n := _max_threads()
	if n == 0:
		_start_pump()
		return
	_mutex.lock()
	var waiting := _want.size()
	_mutex.unlock()
	while _running < n and waiting > _running:
		var t := Thread.new()
		if t.start(self, "_work", t) != OK:
			break
		_threads.append(t)
		_running += 1

# (the cover of one song: the kept file, else made and kept)
func _make(song) -> Image:
	var k := key_of(song)
	var path: String = Globals.p(DIR).plus_file(k + ".png")
	var img := Image.new()
	if File.new().file_exists(path) and img.load(path) == OK:
		return _finish(img)
	var src: Image = null
	var old: String = Globals.p(OLD_DIR).plus_file(k + ".png")
	if File.new().file_exists(old):
		var o := Image.new()
		if o.load(old) == OK:
			src = o
	if src == null:
		src = _square(song._decode_cover_pixels())
	if src == null:
		return null
	if src.get_width() != SIZE or src.get_height() != SIZE:
		src.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	src.save_png(path)
	return _finish(src)

static func _finish(img: Image) -> Image:
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	return img

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

func _work(me):
	while true:
		var song = _next_song()
		if song == null:
			break
		var img = _make(song)
		_mutex.lock()
		_done.append([song, key_of(song), img])
		_mutex.unlock()
	call_deferred("_thread_done", me)
	call_deferred("_start_pump")

func _thread_done(t):
	if t != null and t.is_active():
		t.wait_to_finish()
	_threads.erase(t)
	_running = max(0, _running - 1)
	_mutex.lock()
	var more := not _want.empty()
	_mutex.unlock()
	if more:
		_kick()

# (_pump runs every frame while there's work, then lets go)
func _start_pump():
	var tree = Engine.get_main_loop()
	if not tree.is_connected("idle_frame", self, "_pump"):
		tree.connect("idle_frame", self, "_pump")

# main thread, once a frame while there's work: a few finished covers become
# textures (no threads: one cover made here per frame instead)
func _pump():
	if _max_threads() == 0:
		var s = _next_song()
		if s != null:
			var im = _make(s)
			_done.append([s, key_of(s), im])
	_mutex.lock()
	var take: Array = _done.slice(0, PER_FRAME - 1) if _done.size() > 0 else []
	if _done.size() > PER_FRAME:
		_done = _done.slice(PER_FRAME, _done.size() - 1)
	else:
		_done = []
	var more: bool = not _done.empty() or (_max_threads() == 0 and not _want.empty())
	_mutex.unlock()
	for d in take:
		_mutex.lock()
		_asked.erase(d[1])
		_mutex.unlock()
		if d[2] == null:
			continue
		var t := ImageTexture.new()
		t.create_from_image(d[2], Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		_tex[d[1]] = t
		_order.append(d[1])
		while _order.size() > MAX_TEX:
			_tex.erase(_order.pop_front())
		emit_signal("ready", d[0])
	if not more:
		var tree = Engine.get_main_loop()
		if tree.is_connected("idle_frame", self, "_pump"):
			tree.disconnect("idle_frame", self, "_pump")
