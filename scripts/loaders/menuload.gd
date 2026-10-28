extends Node

var leaving: bool = false

var target: String = Rhythia.menu_target

var black_fade_target: bool = false
var black_fade: float = 0

func _ready():
	Rhythia.trail("loading the menu")
	load("res://scripts/game/SoundSpaceMode.gd").end_song() # leaving the song: your own settings back
	load("res://scripts/SpectateSettings.gd").restore() # and yours if you were watching with someone's
	get_tree().paused = false
	if Rhythia.vr:
		target = "res://vr/vrmenu.tscn"
		Rhythia.vr_player.transform.origin = Vector3(0, 0, 0)
	PhysicsServer.set_active(true)
	Input.set_custom_mouse_cursor(null)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	Rhythia.restore_colorset_after_random()
	Rhythia.load_color_txt()
	Rhythia.conmgr_transit = null
	Rhythia.loaded_world = null
	Rhythia.was_replay = Rhythia.replaying
	Rhythia.replaying = false
	if Rhythia.was_replay: Rhythia.restore_prev_state()
	Rhythia.restore_lobby_lead_in()
	if Rhythia.selected_song:
		# the star rater (another thread) may be reading this map right now
		Rhythia.lock_song_notes(Rhythia.selected_song)
		Rhythia.selected_song.discard_notes()
		Rhythia.unlock_song_notes(Rhythia.selected_song)
	Rhythia.replay_path = ""
	$BlackFade.visible = true
	black_fade = 1
	$BlackFade.color = Color(0, 0, 0, black_fade)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var s = Globals.error_sound
	var st = Rhythia.get_stream_with_default("user://loadingmusic", s)
	if st != s:
		$Music.stream = st
		$Music.play()



	var res = RQueue.queue_resource(target)
	if res != OK:
		Rhythia.errorstr = "queue_resource returned %s" % res
		get_tree().change_scene("res://scenes/errors/menuload.tscn")
	# VR: the song scene's files are loaded once here too (and kept), so the
	# first song starts quickly
	if Rhythia.vr and not Rhythia._dep_walked.has(SONG_SCENE):
		if RQueue.queue_resource(SONG_SCENE) == OK:
			_song_too = true

const SONG_SCENE := "res://scenes/song.tscn"
var _song_too := false

var result
var left: bool = false

func _process(delta):

	$Music.volume_db = -8 - (40 * black_fade)
	if black_fade_target and black_fade != 1:
		black_fade = min(black_fade + (delta / 0.3), 1)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	elif not black_fade_target and black_fade != 0:
		black_fade = max(black_fade - (delta / 0.3), 0)
		$BlackFade.color = Color(0, 0, 0, black_fade)

	if not leaving:
		if RQueue.is_ready(target) and (not _song_too or RQueue.is_ready(SONG_SCENE)):
			if _song_too:
				var _song = RQueue.get_resource(SONG_SCENE)
				Rhythia.keep_deps(SONG_SCENE) # (its files; the scene itself is let go)
				_song = null
				_song_too = false
			result = RQueue.get_resource(target)
			Rhythia.keep_deps(target)
			leaving = true
			black_fade_target = true
			if not (result is Object):
				Rhythia.errorstr = "get_resource returned non-object (probably null)"
				var broken := _find_broken(target, {})
				if broken != "":
					Rhythia.errorstr += "\nbroken file: " + broken
				get_tree().change_scene("res://scenes/errors/menuload.tscn")

	if leaving and result and black_fade == 1:
		get_tree().change_scene_to(result)


# The first file in `path`'s dependency tree that fails to load (deepest first),
# shown on the error screen so a report says what broke.
func _find_broken(path: String, seen: Dictionary) -> String:
	if seen.has(path) or not path.begins_with("res://"):
		return ""
	seen[path] = true
	for dep in ResourceLoader.get_dependencies(path):
		var found := _find_broken(String(dep).split("::")[0], seen)
		if found != "":
			return found
	if not ResourceLoader.exists(path) or load(path) == null:
		return path
	return ""
