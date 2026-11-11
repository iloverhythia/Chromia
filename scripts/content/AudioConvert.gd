extends Node
# Songs the engine can't decode: .m4a (AAC), FLAC, raw AAC and Opus. Godot 3
# plays only Ogg Vorbis, MP3 and WAV, and has no decoder for these, so a map
# whose song is one of them came up as "broken audio".
#
# Such a song is sent once to the Chromia server, which sends it back as Ogg
# Vorbis (savia_web src/videoconvert.js convertAudio, ?to=ogg: still in time
# with the notes), and the result is kept in user://caches/audio_convert under
# the song's own fingerprint. From then on the map plays from that file, with
# no connection needed:
#   AudioLoader.load_buffer finds it by itself, every time the song is loaded;
#   the loading screen (songload.gd) and the menu's Play Music start the
#   conversion the first time; Add Song converts a picked .m4a before the map
#   is made, so the new map holds the Ogg and needs none of this.
#
#   AudioConvert.needed(bytes)   the song is one of these and isn't kept yet
#   AudioConvert.start(bytes)    -> a node; "finished"(ok, error or the .ogg's path)

signal finished(ok, text)

const URL := "https://savia.nysr.host/savia-convert-audio?to=ogg"
const DIR := "user://caches/audio_convert"
const MAX_BYTES := 40 * 1024 * 1024
const FORMATS := ["m4a", "flac", "aac", "opus"]

# what the bytes are, if it's one of ours ("" otherwise). By content, never by name.
static func kind(b: PoolByteArray) -> String:
	if b.size() < 40:
		return ""
	if b[4] == 0x66 and b[5] == 0x74 and b[6] == 0x79 and b[7] == 0x70: # "ftyp": m4a, mp4, 3gp
		return "m4a"
	if b[0] == 0x66 and b[1] == 0x4c and b[2] == 0x61 and b[3] == 0x43: # "fLaC"
		return "flac"
	# raw AAC (ADTS): the same 12 set bits an MP3 frame starts with, but its
	# "layer" bits are 00, which an MP3 never has
	if b[0] == 0xff and (b[1] & 0xf6) == 0xf0:
		return "aac"
	# Opus in an Ogg file ("OggS", then "OpusHead" in its first page)
	if b[0] == 0x4f and b[1] == 0x67 and b[2] == 0x67 and b[3] == 0x53 and b.subarray(28, 35).get_string_from_ascii() == "OpusHead":
		return "opus"
	return ""

static func key_of(b: PoolByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode()

static func path_of(b: PoolByteArray) -> String:
	return Globals.p("%s/%s.ogg" % [DIR, key_of(b)])

# the converted song, if it has been made: an AudioStreamOGGVorbis, or null
static func cached(b: PoolByteArray) -> AudioStream:
	var f := File.new()
	var p := path_of(b)
	if not f.file_exists(p) or f.open(p, File.READ) != OK:
		return null
	var data: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	if data.size() < 64 or data.subarray(0, 3).get_string_from_ascii() != "OggS":
		return null
	var s := AudioStreamOGGVorbis.new()
	s.data = data
	return s

static func needed(b) -> bool:
	return b is PoolByteArray and kind(b) != "" and not File.new().file_exists(path_of(b))

# One conversion at a time per song: asking again while it runs gives the same node.
static func start(b: PoolByteArray) -> Node:
	var root: Node = Engine.get_main_loop().root
	var key := key_of(b)
	var name_ := "AudioConvert_" + key.left(16)
	if root.has_node(name_):
		return root.get_node(name_)
	var c = load("res://scripts/content/AudioConvert.gd").new()
	c.name = name_
	c._key = key
	root.add_child(c)
	c.call_deferred("_begin", b)
	return c

var _key := ""
var done := false
var ok := false
var text := ""

func _begin(b: PoolByteArray):
	if kind(b) == "":
		return _done(false, "that isn't a song this needs to convert")
	if b.size() > MAX_BYTES:
		return _done(false, "the song is too big to convert (40 MB at most)")
	var http := HTTPRequest.new()
	http.use_threads = OS.can_use_threads() # (megabytes each way: off the game's main thread)
	http.timeout = 180
	add_child(http)
	http.connect("request_completed", self, "_on_answer")
	if http.request_raw(URL, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, b) != OK:
		_done(false, "couldn't reach the Chromia server")

func _on_answer(result: int, code: int, _headers, body: PoolByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return _done(false, "couldn't reach the Chromia server%s" % (" (%d)" % code if code else ""))
	if body.size() < 64 or body.subarray(0, 3).get_string_from_ascii() != "OggS":
		var why := "the server couldn't convert it"
		var j = JSON.parse(body.get_string_from_utf8())
		if j.error == OK and j.result is Dictionary and String(j.result.get("error", "")) != "":
			why = Globals.s(j.result.get("error"))
		return _done(false, why)
	var d := Directory.new()
	if not d.dir_exists(Globals.p(DIR)):
		d.make_dir_recursive(Globals.p(DIR))
	var p: String = Globals.p("%s/%s.ogg" % [DIR, _key])
	# (written under another name first: a half-written file is never taken for the song)
	var f := File.new()
	if f.open(p + ".part", File.WRITE) != OK:
		return _done(false, "couldn't save the converted song")
	f.store_buffer(body)
	f.close()
	d.remove(p)
	if d.rename(p + ".part", p) != OK:
		return _done(false, "couldn't save the converted song")
	_done(true, p)

func _done(is_ok: bool, t: String):
	done = true
	ok = is_ok
	text = t
	emit_signal("finished", is_ok, t)
	queue_free()
