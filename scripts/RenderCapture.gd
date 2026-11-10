extends Node

# Making a video one frame at a time (Save video's link, the game view:
# WebReplay.gd). Recording the screen as
# it plays dropped frames whenever the computer fell behind (smooth, then
# 40 fps for a few seconds). Here the song moves exactly 1/fps of a second
# each frame however long the frame takes (Rhythia.render_fps: NoteManager's
# clock), every frame is kept, and the sound is put together afterwards from
# what played when:
#   music: the song's own clock (where the song is each frame, at what speed;
#          a jump, a pause and the end start / stop a piece), so it is in
#          time with the notes whatever the speakers did meanwhile;
#   other sounds (hitsounds, misses, the fail sound...): each one that starts,
#          from any sound player in the game, at the frame it started.
# While it runs the game's own sound is off (it doesn't keep time with the
# frames) and the music isn't re-synced.
#
# begin(fps, fixed_engine) / end() -> { "frames", "fps", "music": [...],
# "sounds": [...], "files": { id: { "stream", "ext" } } } (see end()).

signal frame_drawn(index)

const LONG := 8.0 # seconds: longer sounds are "long" (the game's renderer mixes them with ffmpeg)

var fps := 60
var frame := 0 # frames drawn since begin(): the one being made now
var running := false
var _fixed_engine := true # the engine's own clock is fixed too (the browser: --fixed-fps)
var _last_usec := 0

var music := [] # { t, end, from, pitch, keep_pitch, db, sid }
var sounds := [] # { t, sid, pitch, db }
var files := {} # sid -> { stream, ext, length }
var _ids := {} # stream instance id -> sid
var _players := {} # player instance id -> { node, playing, pos, stream }
var _seg = null # the music piece playing now

var _was_mute := false
var _was_desync := false

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = 1000 # after the game's own scripts, so this frame's sounds are seen

# fixed_engine: false when the engine's own clock isn't fixed (--fixed-fps):
# the rest of the engine (effects, particles) is then kept close to 1/fps a
# frame with its time scale
func begin(p_fps: int, fixed_engine: bool):
	fps = p_fps
	_fixed_engine = fixed_engine
	frame = 0
	music = []
	sounds = []
	files = {}
	_ids = {}
	_players = {}
	_seg = null
	running = true
	Rhythia.render_fps = fps
	Rhythia.render_step_ok = true
	_was_desync = Rhythia.disable_desync
	Rhythia.disable_desync = true
	_was_mute = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	_last_usec = OS.get_ticks_usec()
	_watch(get_tree().root)
	if not get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().connect("node_added", self, "_on_node_added")
	if not VisualServer.is_connected("frame_post_draw", self, "_on_frame_drawn"):
		VisualServer.connect("frame_post_draw", self, "_on_frame_drawn")

func end() -> Dictionary:
	if running:
		_close_seg(_t())
	running = false
	Rhythia.render_fps = 0
	Rhythia.render_step_ok = true
	Rhythia.disable_desync = _was_desync
	AudioServer.set_bus_mute(0, _was_mute)
	Engine.time_scale = 1.0
	if get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().disconnect("node_added", self, "_on_node_added")
	if VisualServer.is_connected("frame_post_draw", self, "_on_frame_drawn"):
		VisualServer.disconnect("frame_post_draw", self, "_on_frame_drawn")
	return { "frames": frame, "fps": fps, "music": music, "sounds": sounds, "files": files }

func _exit_tree():
	if running:
		end()

func _t() -> float:
	return float(frame) / float(fps)

func _on_frame_drawn():
	if not running:
		return
	var i := frame
	frame += 1
	Rhythia.render_step_ok = true
	emit_signal("frame_drawn", i)

# ── the sound players ──
func _watch(n: Node):
	if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
		_players[n.get_instance_id()] = { "node": n, "playing": n.playing, "pos": 0.0, "stream": n.stream }
	for c in n.get_children():
		_watch(c)

func _on_node_added(n: Node):
	if running and (n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D):
		_players[n.get_instance_id()] = { "node": n, "playing": false, "pos": 0.0, "stream": null }

func _process(_delta):
	if not running:
		return
	# the rest of the engine near 1/fps a frame (the game's renderer)
	var u := OS.get_ticks_usec()
	var real: float = max(float(u - _last_usec) / 1000000.0, 0.001)
	_last_usec = u
	if not _fixed_engine:
		Engine.time_scale = clamp((1.0 / float(fps)) / real, 0.05, 8.0)
	# (this frame's song step is taken: the next waits for this frame to be drawn)
	Rhythia.render_step_ok = false
	var t := _t()
	var spawn = _spawn()
	var music_node = spawn.get_node_or_null("Music") if spawn != null else null
	_track_music(spawn, music_node, t)
	for id in _players.keys():
		var s: Dictionary = _players[id]
		var p = s.node
		if not is_instance_valid(p):
			_players.erase(id)
			continue
		if p == music_node:
			continue
		var playing: bool = p.playing
		var pos: float = p.get_playback_position() if playing else 0.0
		if playing and p.stream != null:
			if not s.playing or p.stream != s.stream:
				_add_sound(p, t)
			elif pos + 0.02 < float(s.pos):
				# played again while still playing: seen a frame late (the position
				# only goes back once the sound is mixed)
				_add_sound(p, max(t - 1.0 / float(fps), 0.0))
		s.playing = playing
		s.pos = pos
		s.stream = p.stream

func _add_sound(p, t: float):
	var sid := _sound_id(p.stream)
	if sid == "":
		return
	var db: float = p.unit_db if p is AudioStreamPlayer3D else p.volume_db
	sounds.append({ "t": t, "sid": sid, "pitch": float(p.pitch_scale), "db": db + _bus_db(String(p.bus)) })

# the bus's volume and the ones it goes through, not the main volume (the
# video is made at full volume, with the player's balance of music and sounds)
func _bus_db(bus: String) -> float:
	var db := 0.0
	var guard := 0
	while bus != "" and guard < 16:
		guard += 1
		var i := AudioServer.get_bus_index(bus)
		if i <= 0:
			break
		if AudioServer.is_bus_mute(i):
			return -80.0
		db += AudioServer.get_bus_volume_db(i)
		bus = String(AudioServer.get_bus_send(i))
	return db

# ── the music: from the song's clock ──
func _spawn():
	var cur = get_tree().current_scene
	return cur.get_node_or_null("Game/Spawn") if cur != null else null

func _track_music(spawn, m, t: float):
	if spawn == null or m == null or m.stream == null:
		_close_seg(t)
		return
	var on: bool = bool(spawn.get("music_started")) and float(spawn.get("pause_state")) >= 0.0
	if not on:
		_close_seg(t)
		return
	var song_s: float = float(spawn.get("ms")) / 1000.0
	var pitch: float = float(m.pitch_scale)
	if _seg != null:
		var expect: float = float(_seg.from) + (t - float(_seg.t)) * float(_seg.pitch)
		if abs(song_s - expect) <= 0.03 and abs(pitch - float(_seg.pitch)) < 0.001 and _seg.stream == m.stream:
			return
		_close_seg(t)
	_seg = { "t": t, "from": song_s, "pitch": pitch, "keep_pitch": bool(Rhythia.retain_song_pitch),
		"db": float(m.volume_db) + _bus_db(String(m.bus)), "sid": _sound_id(m.stream), "stream": m.stream }

func _close_seg(t: float):
	if _seg == null:
		return
	var s: Dictionary = _seg
	_seg = null
	if String(s.sid) == "" or t <= float(s.t):
		return
	# (the song starts before its audio does: the lead-in)
	var from: float = float(s.from)
	var start: float = float(s.t)
	if from < 0.0:
		start += -from / max(float(s.pitch), 0.01)
		from = 0.0
	if start >= t:
		return
	music.append({ "t": start, "end": t, "from": from, "pitch": s.pitch, "keep_pitch": s.keep_pitch, "db": s.db, "sid": s.sid })

# ── the sounds' own files ──
# stream -> an id for it ("" when it can't be saved: not MP3 / Ogg / WAV)
func _sound_id(stream) -> String:
	if stream == null:
		return ""
	if stream is AudioStreamRandomPitch:
		stream = stream.audio_stream
		if stream == null:
			return ""
	var key: int = stream.get_instance_id()
	if _ids.has(key):
		return String(_ids[key])
	var ext := ""
	if stream is AudioStreamMP3:
		ext = "mp3"
	elif stream is AudioStreamOGGVorbis:
		ext = "ogg"
	elif stream is AudioStreamSample and stream.format != AudioStreamSample.FORMAT_IMA_ADPCM:
		ext = "wav"
	var sid := ""
	if ext != "":
		sid = "s%d" % files.size()
		files[sid] = { "stream": stream, "ext": ext, "length": float(stream.get_length()) }
	_ids[key] = sid
	return sid

# a sound's file as bytes (MP3 / Ogg as they are, a WAV made for a sample)
static func file_bytes(info: Dictionary) -> PoolByteArray:
	var stream = info.stream
	if info.ext == "mp3" or info.ext == "ogg":
		return stream.data
	return wav_bytes(stream)

static func wav_bytes(s: AudioStreamSample) -> PoolByteArray:
	var pcm: PoolByteArray = s.data
	var ch := 2 if s.stereo else 1
	var bits := 16 if s.format == AudioStreamSample.FORMAT_16_BITS else 8
	if bits == 8:
		# Godot keeps 8-bit samples signed, a WAV unsigned
		var u := PoolByteArray()
		u.resize(pcm.size())
		for i in pcm.size():
			u[i] = (pcm[i] + 128) & 255
		pcm = u
	var rate := int(s.mix_rate)
	var out := StreamPeerBuffer.new()
	out.big_endian = false
	out.put_data("RIFF".to_ascii())
	out.put_32(36 + pcm.size())
	out.put_data("WAVEfmt ".to_ascii())
	out.put_32(16)
	out.put_16(1)
	out.put_16(ch)
	out.put_32(rate)
	out.put_32(rate * ch * bits / 8)
	out.put_16(ch * bits / 8)
	out.put_16(bits)
	out.put_data("data".to_ascii())
	out.put_32(pcm.size())
	out.put_data(pcm)
	return out.data_array
