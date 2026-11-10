extends Button

var has_auto_previewed:bool = false

func _pressed():
	if !Rhythia.selected_song: return
	if !$Song.playing:
		$Song.stream = Rhythia.selected_song.stream()
		if $Song.stream == Globals.error_sound and _convert_then_play():
			return
		if $Song.stream == null:
			# No audio for this map (the built-in maps ship without their music).
			text = "Play Music"
			return
		$Song.volume_db = -55
		menu_pause()
		$Song.play($Song.stream.get_length()*0.4)
		$Song.pitch_scale = Globals.speed_multi[Rhythia.mod_speed_level]
		text = "Stop Playing"
	else:
		$Song.stop()
		text = "Play Music"
		menu_resume()

# A song the engine can't decode (.m4a, FLAC...): converted by the Chromia
# server once (AudioConvert.gd), then played if the map is still selected.
# -> true when a conversion was started
func _convert_then_play() -> bool:
	var s = Rhythia.selected_song
	var AudioConvert = load("res://scripts/content/AudioConvert.gd")
	var buf = s.get_music_buffer()
	if not AudioConvert.needed(buf):
		return false
	$Song.stream = null
	text = "Getting the song..."
	var job = AudioConvert.start(buf)
	if not job.is_connected("finished", self, "_on_song_converted"):
		job.connect("finished", self, "_on_song_converted", [s])
	return true

func _on_song_converted(ok: bool, why: String, s):
	text = "Play Music"
	if not ok:
		Globals.notify(Globals.NOTIFY_WARN, "This map's song couldn't be converted: %s." % why, "Song")
	elif s == Rhythia.selected_song and not $Song.playing:
		_pressed()

var song = Rhythia.selected_song

func on_path_press():
	has_auto_previewed = false
	$Song.stop()
	text = "Play Music"
	menu_resume()
	

func _process(delta):
	var trg = Rhythia.music_volume_db
	if $MenuSong.playing:
		_menu_last_pos = $MenuSong.get_playback_position()
		if $MenuSong.volume_db != trg:
			$MenuSong.volume_db = min($MenuSong.volume_db + (delta * 75),trg)

# --- The menu music -------------------------------------------------------------
# A map preview pauses it and it carries on from the same spot afterwards;
# turning it off (Settings) stops it until it's turned back on. The next song
# of the playlist starts only when a song really reaches its end: Godot 3
# also sends "finished" when a player is stopped, which used to start the next
# song every time the music was paused or turned off.
var _menu_pos := 0.0 # where it was paused
var _menu_last_pos := 0.0 # where it was last frame

func menu_pause():
	if $MenuSong.playing:
		_menu_pos = $MenuSong.get_playback_position()
	$MenuSong.stop()

func menu_resume():
	if not Rhythia.play_menu_music or $Song.playing or $MenuSong.playing:
		return
	if $MenuSong.stream == null:
		return
	$MenuSong.volume_db = -45
	$MenuSong.play(_menu_pos)
	_menu_pos = 0.0

func _menu_song_finished():
	var length: float = $MenuSong.stream.get_length() if $MenuSong.stream else 0.0
	if length > 0.0 and length - _menu_last_pos > 1.0:
		return # stopped (paused / turned off), not the end of the song
	_menu_last_pos = 0.0
	_menu_pos = 0.0
	$MenuSong.stream = Rhythia.next_menu_track()
	if Rhythia.play_menu_music and not $Song.playing:
		$MenuSong.play()

func _on_menu_track_ready(_path):
	if not is_inside_tree() or $MenuSong.stream != null:
		return
	$MenuSong.stream = Rhythia.next_menu_track()
	_menu_pos = 0.0
	menu_resume()

func upd_mm():
	if Rhythia.play_menu_music: menu_resume()
	else: menu_pause()

# Selecting maps quickly (random map spam, scrolling) used to load and swap a
# new song stream on every click. Now the preview waits until the selection
# has stayed put for a moment, and only the last map's audio gets loaded.
const PREVIEW_DELAY := 0.25
var _preview_timer: SceneTreeTimer = null

func upd(s=null):
	if s == song:
		return
	if $Song.playing:
		$Song.stop()
		_preview_was_playing = true
	_preview_timer = get_tree().create_timer(PREVIEW_DELAY)
	_preview_timer.connect("timeout", self, "_do_upd", [_preview_timer, s])

var _preview_was_playing := false
func _do_upd(t, s):
	if t != _preview_timer or not is_inside_tree():
		return
	_preview_timer = null
	var was_playing := _preview_was_playing
	_preview_was_playing = false
	if Rhythia.selected_song == null:
		return
	if s != song:
		if was_playing or $Song.playing or (Rhythia.auto_preview_song and !has_auto_previewed):
			if Rhythia.auto_preview_song: has_auto_previewed = true
			$Song.stop()
			menu_pause()
			$Song.volume_db = -55
			$Song.stream = Rhythia.selected_song.stream()
			if $Song.stream == Globals.error_sound:
				has_auto_previewed = false
				menu_resume()
				return
			if ($Song.stream is AudioStreamMP3 or $Song.stream is AudioStreamOGGVorbis):
				$Song.stream.loop = true
			$Song.pitch_scale = Globals.speed_multi[Rhythia.mod_speed_level]
#			print(Rhythia.mod_speed_level)
			if $Song.stream:
				$Song.play($Song.stream.get_length()/3)
				text = "Stop Playing"
			else:
				text = "Play Music"
				menu_resume()
		else:
			text = "Play Music"
			menu_resume()
		song = Rhythia.selected_song

func _ready():
	Rhythia.connect("selected_song_changed",self,"upd")
	Rhythia.connect("speed_mod_changed",self,"upd")
	Rhythia.connect("menu_music_state_changed",self,"upd_mm")
	# a custom menu song loops; otherwise the built-in songs play in a random
	# order, one after another (Savia.gd: next_menu_track). Read on a thread:
	# reading an MP3 goes through the whole file (it held up the menu opening)
	_ready_ms = OS.get_ticks_msec()
	if OS.can_use_threads():
		_mm_thread = Thread.new()
		if _mm_thread.start(self, "_read_menu_song") != OK:
			_mm_thread = null
	if _mm_thread == null:
		_menu_song_read(_read_menu_song(null))

var _mm_thread: Thread = null
var _ready_ms := 0

func _read_menu_song(_u):
	var custom = Rhythia.get_stream_with_default("user://menu", null)
	var out := [custom != null, custom if custom != null else Rhythia.next_menu_track()]
	if _mm_thread != null:
		call_deferred("_menu_song_thread_done")
	return out

func _menu_song_thread_done():
	if _mm_thread == null:
		return
	var res = _mm_thread.wait_to_finish()
	_mm_thread = null
	if is_inside_tree():
		_menu_song_read(res)

func _exit_tree():
	if _mm_thread != null and _mm_thread.is_active():
		_mm_thread.wait_to_finish()
	_mm_thread = null

func _menu_song_read(res: Array):
	var custom = res[1] if res[0] else null
	if custom:
		$MenuSong.stream = custom
		if custom is AudioStreamSample: custom.loop_mode = 1
		else: custom.loop = true
	else:
		$MenuSong.stream = res[1]
		$MenuSong.connect("finished", self, "_menu_song_finished")
		# none downloaded yet (the first start): the first one to arrive plays
		var mm = load("res://scripts/MenuMusic.gd").get_or_start()
		if not mm.is_connected("track_ready", self, "_on_menu_track_ready"):
			mm.connect("track_ready", self, "_on_menu_track_ready")
	if Rhythia.play_menu_music:
		# (half a second after the menu opened, as before)
		var wait: float = 0.5 - (OS.get_ticks_msec() - _ready_ms) / 1000.0
		if wait > 0.0:
			yield(get_tree().create_timer(wait), "timeout")
		if is_inside_tree() and !$Song.playing and !$MenuSong.playing and Rhythia.play_menu_music:
			$MenuSong.play()
