extends Button

var has_auto_previewed:bool = false

func _pressed():
	if !Rhythia.selected_song: return
	if !$Song.playing:
		$Song.stream = Rhythia.selected_song.stream()
		if $Song.stream == null:
			# No audio for this map (the built-in maps ship without their music).
			text = "Play Music"
			return
		$Song.volume_db = -55
		$MenuSong.stop()
		$Song.play($Song.stream.get_length()*0.4)
		$Song.pitch_scale = Globals.speed_multi[Rhythia.mod_speed_level]
		text = "Stop Playing"
	else:
		$Song.stop()
		text = "Play Music"
		if Rhythia.play_menu_music and !$MenuSong.playing:
			$MenuSong.volume_db = -45
			$MenuSong.play()

var song = Rhythia.selected_song

func on_path_press():
	has_auto_previewed = false
	$Song.stop()
	text = "Play Music"
	

func _process(delta):
	var trg = Rhythia.music_volume_db
	if $MenuSong.playing and $MenuSong.volume_db != trg:
		$MenuSong.volume_db = min($MenuSong.volume_db + (delta * 75),trg)

func upd_mm():
	if Rhythia.play_menu_music and !$Song.playing:
		$MenuSong.volume_db = -45
		$MenuSong.play()
	else: $MenuSong.stop()

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
			$MenuSong.stop()
			$Song.volume_db = -55
			$Song.stream = Rhythia.selected_song.stream()
			if $Song.stream == Globals.error_sound:
				has_auto_previewed = false
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
		else:
			text = "Play Music"
			if Rhythia.play_menu_music and !$MenuSong.playing:
				$MenuSong.volume_db = -45
				$MenuSong.play()
		song = Rhythia.selected_song

func _ready():
	Rhythia.connect("selected_song_changed",self,"upd")
	Rhythia.connect("speed_mod_changed",self,"upd")
	Rhythia.connect("menu_music_state_changed",self,"upd_mm")
	$MenuSong.stream = Rhythia.get_stream_with_default("user://menu",load("res://assets/sfx/music/menu_loop.ogg"))
	if $MenuSong.stream is AudioStreamSample: $MenuSong.stream.loop_mode = 1
	else: $MenuSong.stream.loop = true
	if Rhythia.play_menu_music:
		yield(get_tree().create_timer(0.5),"timeout")
		if !$Song.playing:
#			$MenuSong.volume_db = -45
			$MenuSong.play()
