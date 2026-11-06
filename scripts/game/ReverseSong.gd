extends Node

# The Reverse mod's song: the map's music backwards.
#
# Chromia can't decode songs itself (MP3 / OGG), so the song is read through
# the audio engine, like the map editor's waveform (editor/ssqe/SSQEAudio.gd):
# it plays silently in several slices at once at 2x speed, each slice through
# a bus that records it (AudioEffectCapture). At 2x the recording keeps every
# 2nd sample (~22-24 kHz, plenty for a song played backwards), so a 3 minute
# song is read in about 8 seconds on PC. The recording is turned around, made
# into a sound (16 bit) and kept in user://caches/reverse, so the same song
# backwards is ready straight away next time.
#
# The song loader (loaders/songload.gd) makes one while showing its progress
# bar; Game.gd plays Rhythia.reverse_stream and turns the notes around
# (each note at length - time).

signal progress(f)
signal done(stream)

const PITCH := 2.0
const CACHE_DIR := "user://caches/reverse"
const MAGIC := "CRV1"
const KEEP := 4 # songs kept backwards in the cache

var _stream: AudioStream
var _length := 0.0 # the song's seconds
var _total_ms := 0.0 # the length played backwards (the map can go past the song)
var _rate := 22050.0
var _segs := []
var _state := "idle" # capturing, converting, done
var _started := 0
var _key := ""
# converting
var _frames := PoolVector2Array()
var _pos := 0
var _buf: StreamPeerBuffer

static func _key_for(song) -> String:
	return ("%s|%s|%d" % [String(song.id), String(song.musicFile), int(song.last_ms)]).md5_text()

static func cache_path(song) -> String:
	return CACHE_DIR + "/" + _key_for(song) + ".crv"

# the song backwards, from the cache (null when it isn't there)
static func cached(song, total_ms: float) -> AudioStreamSample:
	var f := File.new()
	var p: String = Globals.p(cache_path(song)) if Globals.has_method("p") else cache_path(song)
	if f.open(p, File.READ) != OK:
		return null
	if f.get_buffer(4).get_string_from_ascii() != MAGIC:
		f.close()
		return null
	var rate := f.get_32()
	var ms := f.get_32()
	var data := f.get_buffer(f.get_len() - f.get_position())
	f.close()
	if abs(ms - total_ms) > 2.0 or rate <= 0 or data.size() < 4:
		return null
	return _sample(data, rate)

static func _sample(data: PoolByteArray, rate: int) -> AudioStreamSample:
	var s := AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.stereo = true
	s.mix_rate = rate
	s.data = data
	return s

# how long the map plays backwards: the song, or the map when it goes past it
static func total_ms(song, stream: AudioStream) -> float:
	var len_ms: float = stream.get_length() * 1000.0 if stream != null else 0.0
	return round(max(len_ms, float(song.last_ms) + 1000.0))

func start(song, stream: AudioStream):
	_stream = stream
	_key = _key_for(song)
	_length = stream.get_length() if stream != null else 0.0
	_total_ms = total_ms(song, stream)
	if stream == null or _length <= 0.0:
		_finish(null)
		return
	var sink := _bus("RevSink", "Master")
	AudioServer.set_bus_mute(sink, true)
	var count := 3 if Rhythia.device("mobile") else 12
	count = int(clamp(ceil(_length / 12.0), 1, count))
	_rate = AudioServer.get_mix_rate() / PITCH
	var slice := _length / count
	_segs = []
	for i in count:
		var b := _bus("RevCap%d" % i, "RevSink")
		var cap := _capture(b)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "RevCap%d" % i
		p.pitch_scale = PITCH
		add_child(p)
		_segs.append({"player": p, "cap": cap, "parts": [], "got": 0, "from": i * slice,
			"need": int(ceil(slice * _rate)) if i < count - 1 else int(ceil((_length - i * slice) * _rate)), "done": false})
	AudioServer.lock()
	for sg in _segs:
		sg.player.play(sg.from)
		sg.cap.clear_buffer()
	AudioServer.unlock()
	_started = OS.get_ticks_msec()
	_state = "capturing"

func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i

func _capture(bus: int) -> AudioEffectCapture:
	for k in AudioServer.get_bus_effect_count(bus):
		var e = AudioServer.get_bus_effect(bus, k)
		if e is AudioEffectCapture:
			return e
	var c := AudioEffectCapture.new()
	c.buffer_length = 4.0
	AudioServer.add_bus_effect(bus, c)
	return c

func _process(_d):
	if _state == "capturing":
		var all := true
		var got := 0
		var need := 0
		for sg in _segs:
			need += sg.need
			if not sg.done:
				var n: int = sg.cap.get_frames_available()
				if n > 0:
					sg.parts.append(sg.cap.get_buffer(n))
					sg.got += n
				if sg.got >= sg.need or (not sg.player.playing and n == 0 and OS.get_ticks_msec() - _started > 500):
					sg.done = true
					sg.player.stop()
				else:
					all = false
			got += min(sg.got, sg.need)
		emit_signal("progress", 0.8 * float(got) / max(1.0, float(need)))
		if OS.get_ticks_msec() - _started > 180000:
			_finish(null) # (something's wrong: the map plays with its song as it is)
			return
		if all:
			_join()
	elif _state == "converting":
		_convert_some()

# the slices as one recording, turned around, with silence first when the map
# goes on past the end of the song
func _join():
	var whole := PoolVector2Array()
	for sg in _segs:
		var r := PoolVector2Array()
		for part in sg.parts:
			r.append_array(part)
		if r.size() > sg.need:
			r.resize(sg.need)
		whole.append_array(r)
		sg.player.queue_free()
	_segs = []
	whole.invert()
	var pad := int(max(0.0, (_total_ms / 1000.0 - _length) * _rate))
	_frames = PoolVector2Array()
	if pad > 0:
		_frames.resize(pad)
		for i in pad:
			_frames[i] = Vector2()
	_frames.append_array(whole)
	_buf = StreamPeerBuffer.new()
	_buf.resize(_frames.size() * 4)
	_buf.seek(0)
	_pos = 0
	_state = "converting"

# float frames to 16 bit sound, a piece each frame (the loading screen keeps moving)
func _convert_some():
	var t0 := OS.get_ticks_msec()
	var n := _frames.size()
	var f := _frames
	var b := _buf
	while _pos < n and OS.get_ticks_msec() - t0 < 12:
		var end: int = min(n, _pos + 8192)
		for i in range(_pos, end):
			var v: Vector2 = f[i]
			b.put_16(int(clamp(v.x, -1.0, 1.0) * 32767.0))
			b.put_16(int(clamp(v.y, -1.0, 1.0) * 32767.0))
		_pos = end
	emit_signal("progress", 0.8 + 0.2 * float(_pos) / max(1.0, float(n)))
	if _pos >= n:
		var data := _buf.data_array
		_save(data)
		_frames = PoolVector2Array()
		_finish(_sample(data, int(_rate)))

func _save(data: PoolByteArray):
	var dir := Directory.new()
	var root: String = Globals.p(CACHE_DIR) if Globals.has_method("p") else CACHE_DIR
	dir.make_dir_recursive(root)
	var f := File.new()
	if f.open(root + "/" + _key + ".crv", File.WRITE) != OK:
		return
	f.store_buffer(MAGIC.to_ascii())
	f.store_32(int(_rate))
	f.store_32(int(_total_ms))
	f.store_buffer(data)
	f.close()
	# only the last few are kept (each is ~5 MB a minute)
	var files := []
	if dir.open(root) == OK:
		dir.list_dir_begin(true, true)
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".crv"):
				files.append([File.new().get_modified_time(root + "/" + fn), fn])
			fn = dir.get_next()
		dir.list_dir_end()
	files.sort_custom(self, "_newer")
	for i in range(KEEP, files.size()):
		dir.remove(root + "/" + files[i][1])

func _newer(a, b) -> bool:
	return a[0] > b[0]

func cancel():
	for sg in _segs:
		if is_instance_valid(sg.player):
			sg.player.stop()
	_segs = []
	_state = "idle"

func _finish(stream):
	_state = "done"
	emit_signal("progress", 1.0)
	call_deferred("emit_signal", "done", stream)
