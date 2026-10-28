extends Node

var leaving: bool = false

var target: String = "res://scenes/song.tscn"
var target2: String = _world_path()

# Settings > VR > Graphics > Simple background: VR songs use the plain VOID
# background (the fastest) whatever background is picked
static func _world_path() -> String:
	var p: String = load("res://scripts/game/SoundSpaceMode.gd").space_path(Rhythia.selected_space.path)
	if Rhythia.vr and Rhythia.vr_simple_bg and p == Rhythia.selected_space.path:
		return "res://assets/worlds/void/void.tscn"
	return p

var black_fade_target: bool = false
var black_fade: float = 0


func _ready():
	load("res://scripts/game/SoundSpaceMode.gd").begin_song() # Sound Space Mode: its look for this song
	print("song loading")
	Rhythia.start_log("loading screen", true)
	Rhythia.pick_random_colorset()
	Rhythia._star_paused = true # background star rating waits until back in the menu
	if not Rhythia.replaying:
		Rhythia.send_analytics_event("map_play", {"map_name": Rhythia.selected_song.name, "client_id": Rhythia.cid}, Rhythia.cid)
	get_tree().paused = false
	if Rhythia.vr:
		Rhythia.vr_player.transform.origin = Vector3(0, -2.5, Rhythia.vr_grid_distance * 2.0) # Settings > VR: grid distance (2 game units a metre)
	$BlackFade.visible = true
	black_fade = 1
	$BlackFade.color = Color(0, 0, 0, black_fade)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var _s = Globals.error_sound







	var res = RQueue.queue_resource(target)
	var res2 = RQueue.queue_resource(target2)
	if res != OK:
		Rhythia.errorstr = "song.tscn queue_resource returned %s" % res
		get_tree().change_scene("res://scenes/errors/songload.tscn")
	elif res2 != OK:
		Rhythia.errorstr = "bg world queue_resource returned %s" % res2
		get_tree().change_scene("res://scenes/errors/songload.tscn")

	Rhythia.refresh_active_sound_streams()
	Rhythia.fail_snd = Rhythia.get_stream_with_default("user://fail", Rhythia.def_fail_snd)
	Rhythia.pb_snd = Rhythia.get_stream_with_default("user://new_best", Rhythia.def_pb_snd)
	Rhythia.menu_bgm = Rhythia.get_stream_with_default("user://menu", Rhythia.def_menu_bgm)
	Rhythia.was_replay = false

var result
var result2
var left: bool = false

var finishing = false
func warning_menu_exit():
	Globals.confirm_prompt.s_back.play()
	yield(Globals.confirm_prompt, "done_closing")
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func progress(v):
	$P.visible = true
	$P.value = v * 100

func finish():
	if finishing: return
	finishing = true
	Rhythia.start_log("scenes loaded")
	result = RQueue.get_resource(target)
	result2 = RQueue.get_resource(target2)
	Rhythia.loaded_world = result2
	# VR: their textures, meshes, sounds... stay loaded for the next song
	Rhythia.keep_deps(target)
	Rhythia.keep_deps(target2, "world")
	if not (result is Object):
		Rhythia.errorstr = "song.tscn get_resource returned non-object (probably null)"
		get_tree().change_scene("res://scenes/errors/songload.tscn")
		return
	if not (result2 is Object):
		Rhythia.errorstr = "bg world get_resource returned non-object (probably null)"

		get_tree().change_scene("res://scenes/errors/songload.tscn")
		return

	# (custom colorsets are reloaded when going back to the menu, not here:
	# reading hundreds of colorset files stuttered the start of the song)

	var lobby_manager = get_node_or_null("/root/LobbyManager")
	var in_lobby_round = lobby_manager != null and lobby_manager.lobby_active
	if Input.is_key_pressed(KEY_L) and not in_lobby_round:
		Rhythia.replaying = true
		Rhythia.replay = Replay.new()

	if Rhythia.replaying:
		Rhythia.save_current_state()
		Rhythia.replay.connect("progress", self, "progress")
		Rhythia.replay.read_data(Rhythia.replay_path)
		# a short replay (< 70 signals) finishes reading without yielding, so
		# done_loading was already emitted: waiting for it would hang here forever
		if not Rhythia.replay.loaded:
			yield(Rhythia.replay, "done_loading")

	black_fade_target = true
	black_fade = 1
	$BlackFade.color = Color(0, 0, 0, black_fade)



	Rhythia.lock_song_notes(Rhythia.selected_song) # the star rater may be reading this map
	var _read = Rhythia.selected_song.read_notes()
	Rhythia.unlock_song_notes(Rhythia.selected_song) # (unlocked before anything that could fail on a broken map)
	var _n_notes: int = _read.size() if _read is Array else 0
	if _n_notes == 0:
		Globals.confirm_prompt.open(
			"This map doesn't have any notes.",
			"Warning",
			[{text = "Return to menu"}]
		)
		var option = yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.close()
		warning_menu_exit()
		return

	Rhythia.start_log("notes read, checking audio")
	if Rhythia.selected_song.stream() == Globals.error_sound:
		Globals.confirm_prompt.open(
			"This map's audio appears to be broken. You can still play the map, but there won't be any music.",
			"Warning",
			[{text = "Return to menu"}, {text = "Continue"}]
		)
		var option = yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.close()
		if option == 0:
			warning_menu_exit()
			return
		else:
			Globals.confirm_prompt.s_next.play()
			yield(Globals.confirm_prompt, "done_closing")


	if Rhythia.show_warnings:
		if (
			(
				Rhythia.smart_trail and
				(Rhythia.trail_detail > 100 or
				(Rhythia.trail_detail * Rhythia.trail_time) > 10)
			) or (Rhythia.trail_detail >= 350)
		):
			var warn_txt = "Your trail detail is set very high. This can cause significant performance issues and possibly crashes."
			if Rhythia.smart_trail:
				warn_txt = "Your trail detail/time is set very high. This can cause significant performance issues and possibly crashes."
			Globals.confirm_prompt.open(
				warn_txt,
				"Warning",
				[{text = "Return to menu"}, {text = "Continue"}]
			)
			var option = yield(Globals.confirm_prompt, "option_selected")
			Globals.confirm_prompt.close()
			if option == 0:
				warning_menu_exit()
				return
			else:
				Globals.confirm_prompt.s_next.play()
				yield(Globals.confirm_prompt, "done_closing")

		if Rhythia.get("approach_rate") <= 0:
			Globals.confirm_prompt.open(
				"You are using a non-standard approach rate. Some things might not work correctly.",
				"Warning",
				[{text = "Return to menu"}, {text = "Continue"}]
			)
			var option = yield(Globals.confirm_prompt, "option_selected")
			Globals.confirm_prompt.close()
			if option == 0:
				warning_menu_exit()
				return
			else:
				Globals.confirm_prompt.s_next.play()
				yield(Globals.confirm_prompt, "done_closing")

		if Rhythia.hitwindow_ms <= 18:
			Globals.confirm_prompt.open(
				"Your hitwindow is set very low. This may lead to some notes being impossible to hit.",
				"Warning",
				[{text = "Return to menu"}, {text = "Continue"}]
			)
			var option = yield(Globals.confirm_prompt, "option_selected")
			Globals.confirm_prompt.close()
			if option == 0:
				warning_menu_exit()
				return
			else:
				Globals.confirm_prompt.s_next.play()
				yield(Globals.confirm_prompt, "done_closing")

	leaving = true

func _process(delta):

	$Music.volume_db = -8 - (50 * black_fade)
	if black_fade_target and black_fade != 1:
		black_fade = min(black_fade + (delta / 0.6), 1)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	elif not black_fade_target and black_fade != 0:
		black_fade = max(black_fade - (delta / 0.3), 0)
		$BlackFade.color = Color(0, 0, 0, black_fade)

	if not leaving and not finishing:
		if RQueue.is_ready(target) and RQueue.is_ready(target2):
			finish()

	if leaving and result and black_fade == 1:
		Rhythia.start_log("switching to song")

		get_tree().change_scene_to(result)
