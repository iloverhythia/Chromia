extends Node

# The Reverse mod's song: the map's music backwards.
#
# Chromia can't decode songs itself (MP3 / OGG), so the song is read through
# the audio engine: it plays silently in many slices at once at 2x speed, each
# slice through a bus that records it. At 2x the recording keeps every 2nd
# sample (~22-24 kHz, plenty for a song played backwards). The recording is
# turned around, made into a sound (16 bit) and kept in user://caches/reverse,
# so the same song backwards is ready straight away next time.
#
# It used to take 8 seconds and more for a 3 minute song: 12 slices, so 7.5 s
# of playing, and then every sample turned into 16 bit by script (4 million
# times round a loop). Now a slice is about SLICE_S long (a 3 minute song is 64
# of them: 1.4 s of playing), and nothing goes sample by sample in script:
# each bus records with AudioEffectRecord, which hands back 16 bit sound made
# by the engine, and the frames are put in reverse order by an Image
# (a frame is 4 bytes, like an RGBA8 pixel: flipped both ways, the pixels are
# in reverse order).
#
# The song loader (loaders/songload.gd) makes one while showing its progress
# bar; Game.gd plays Rhythia.reverse_stream and turns the notes around
# (each note at length - time).

signal progress(f)
signal done(stream)

const PITCH := 2.0
const CACHE_DIR := "user://caches/reverse"
const MAGIC := "CRV1"
const KEEP := 6 # songs kept backwards in the cache
const SLICE_S := 2.8 # a slice of the song, in seconds (played at PITCH)
const ROW := 16384 # frames in a row of the Image that turns them around (an Image's widest)

var _stream: AudioStream
var _length := 0.0 # the song's seconds
var _total_ms := 0.0 # the length played backwards (the map can go past the song)
var _rate := 22050.0
var _segs := []
var _state := "idle" # capturing, converting, done
var _started := 0
var _key := ""
var _wait := 0 # frames left before the recordings are read (their threads end first)

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
	# (each slice is a decoder running at twice the song's speed: fewer on a
	# phone or a headset, whose audio thread has less to spare)
	var most := 24 if (Rhythia.device("mobile") or Rhythia.vr) else 64
	var count := int(clamp(ceil(_length / SLICE_S), 1, most))
	_rate = AudioServer.get_mix_rate() / PITCH
	var slice := _length / count
	_segs = []
	for i in count:
		var b := _bus("RevCap%d" % i, "RevSink")
		var rec := _recorder(b)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "RevCap%d" % i
		p.pitch_scale = PITCH
		add_child(p)
		_segs.append({"player": p, "rec": rec, "from": i * slice, "to": (i + 1) * slice if i < count - 1 else _length,
			"need": int(ceil(slice * _rate)) if i < count - 1 else int(ceil((_length - i * slice) * _rate)), "done": false})
	AudioServer.lock()
	for sg in _segs:
		sg.player.play(sg.from)
		sg.rec.set_recording_active(true)
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

func _recorder(bus: int) -> AudioEffectRecord:
	for k in AudioServer.get_bus_effect_count(bus):
		var e = AudioServer.get_bus_effect(bus, k)
		if e is AudioEffectRecord:
			return e
	var r := AudioEffectRecord.new()
	r.format = AudioStreamSample.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, r)
	return r

# the buses made for this go again (each is mixed every moment for as long as it's there)
func _drop_buses():
	for i in range(AudioServer.bus_count - 1, 0, -1):
		var n: String = AudioServer.get_bus_name(i)
		if n.begins_with("RevCap") or n == "RevSink":
			AudioServer.remove_bus(i)

func _process(_d):
	if _state == "capturing":
		var all := true
		var got := 0.0
		for sg in _segs:
			if not sg.done:
				var pos: float = sg.player.get_playback_position()
				# (a little past its end: what is recorded is cut to its length after)
				if pos >= sg.to + 0.05 or (not sg.player.playing and OS.get_ticks_msec() - _started > 500):
					sg.done = true
					sg.rec.set_recording_active(false)
					sg.player.stop()
				else:
					all = false
					got += clamp((pos - sg.from) / max(0.001, sg.to - sg.from), 0.0, 1.0)
			if sg.done:
				got += 1.0
		emit_signal("progress", 0.9 * got / max(1.0, float(_segs.size())))
		if OS.get_ticks_msec() - _started > 120000:
			cancel()
			_drop_buses()
			_finish(null) # (something's wrong: the map plays with its song as it is)
			return
		if all:
			_state = "joining"
			_wait = 3
	elif _state == "joining":
		_wait -= 1
		if _wait <= 0:
			_join()

# n bytes of silence (a new byte array isn't empty by itself; an Image is)
static func _zeros(n: int) -> PoolByteArray:
	if n <= 0:
		return PoolByteArray()
	var img := Image.new()
	var w: int = min(n, ROW)
	img.create(w, int(ceil(float(n) / w)), false, Image.FORMAT_L8)
	var d := img.get_data()
	return d if d.size() == n else d.subarray(0, n - 1)

# 16 bit stereo frames (4 bytes each) in reverse order
static func reversed(frames: PoolByteArray) -> PoolByteArray:
	var n := frames.size() / 4
	if n <= 1:
		return frames
	# (an Image's rows are full: what is missing goes in front, and comes out at the end)
	var rows := int(ceil(float(n) / ROW))
	var fill := (rows * ROW - n) * 4
	var data := _zeros(fill)
	data.append_array(frames)
	var img := Image.new()
	img.create_from_data(ROW, rows, false, Image.FORMAT_RGBA8, data)
	img.flip_x()
	img.flip_y()
	var out := img.get_data()
	return out if fill == 0 else out.subarray(0, n * 4 - 1)

# the slices as one recording, turned around, with silence first when the map
# goes on past the end of the song
func _join():
	var whole := PoolByteArray()
	var ok := true
	for sg in _segs:
		var smp = sg.rec.get_recording()
		sg.player.queue_free()
		if smp == null or smp.data.size() < 4:
			ok = false
			continue
		var d: PoolByteArray = smp.data
		if d.size() > sg.need * 4:
			d = d.subarray(0, sg.need * 4 - 1)
		whole.append_array(d)
	_segs = []
	_drop_buses()
	if not ok or whole.size() < 4:
		_finish(null)
		return
	var pad := int(max(0.0, (_total_ms / 1000.0 - _length) * _rate))
	var data := _zeros(pad * 4)
	data.append_array(reversed(whole))
	_save(data)
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
		sg.rec.set_recording_active(false)
		if is_instance_valid(sg.player):
			sg.player.stop()
	_segs = []
	_state = "idle"

func _finish(stream):
	_state = "done"
	emit_signal("progress", 1.0)
	call_deferred("emit_signal", "done", stream)
