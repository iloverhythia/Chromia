extends Node

const AndroidFiles = preload("res://scripts/AndroidFiles.gd")

var thread: Thread = Thread.new()
var target: String = Rhythia.menu_target
var leaving: bool = false

func stage(text: String, done: bool = false):
	$Label2.text = text
	if done:

		$Label2.text = "Loading menu"
		var res = RQueue.queue_resource(target)
		if res != OK:
			Rhythia.errorstr = "queue_resource returned %s" % res
			get_tree().change_scene("res://scenes/errors/menuload.tscn")
		# VR: the song scene's files are loaded once here too (and kept), so
		# the first song starts quickly (as menuload.gd does)
		if Rhythia.vr and not Rhythia._dep_walked.has(SONG_SCENE):
			if RQueue.queue_resource(SONG_SCENE) == OK:
				_song_too = true


const SONG_SCENE := "res://scenes/song.tscn"
var _song_too := false

var black_fade_target: bool = false
var black_fade: float = 0

func _ready():






	get_tree().paused = false
	Rhythia.trail("init screen (%s)" % ("content reload" if Rhythia.is_init else "menu reload"))
	if Rhythia.vr:
		# (as menuload.gd does: the menu in the headset, never the flat one,
		# whatever menu was asked for last)
		target = "res://vr/vrmenu.tscn"
		if is_instance_valid(Rhythia.vr_player):
			Rhythia.vr_player.transform.origin = Vector3(0, 0, 0)
		_vr_panel()
	elif Rhythia.boot_vr_wanted():
		# Meta Quest: VR first, before anything is loaded, with the loading
		# panel in the headset (see Rhythia.start_vr_at_boot). After this
		# function: nodes can't be added to the root while it sets up.
		call_deferred("_boot_vr")
	$BlackFade.visible = true
	black_fade = 1
	$BlackFade.color = Color(0, 0, 0, black_fade)
	Rhythia.connect("init_stage_reached", self, "stage")
	var s = Globals.error_sound




	# Asked once a run. This screen also comes up for a profile switch, a skin
	# and Reload Content, and asking again each time makes Android open (and at
	# once close) its permission screen over the game: on a Quest that takes
	# the game out of focus for a moment, and at times left the headset black.
	if not Engine.has_meta("permissions_asked"):
		Engine.set_meta("permissions_asked", true)
		if not Rhythia.vr and AndroidFiles.ask_at_start_ok():
			OS.request_permissions()
	# (not in VR: changing the window while the headset runs left it black)
	if ProjectSettings.get_setting("application/config/auto_maximize") and Rhythia.auto_maximize and not Rhythia.vr: OS.window_maximized = true


	if not Rhythia.is_init:
		stage("", true)
		return
	elif Rhythia.first_init_done:
		if not OS.can_use_threads() or thread.start(Rhythia, "do_init") != OK:
			Rhythia.call_deferred("do_init") # no threads (web build)

	Rhythia.is_init = false

	if ProjectSettings.get_setting("application/config/discord_rpc"):
		var activity = Discord.Activity.new()
		activity.set_type(Discord.ActivityType.Playing)
		activity.set_details("Initialization")

		if Rhythia.do_archive_convert: activity.set_state("Mass-converting songs")
		elif Rhythia.first_init_done: activity.set_state("Reloading content")
		else: activity.set_state("Starting the game")

		var assets = activity.get_assets()
		assets.set_large_image(Globals.DISCORD_ICON)

		Discord.activity_manager.update_activity(activity)

func _exit_tree():
	if thread.is_active():
		thread.wait_to_finish()

# In VR this loading screen is only on the computer's window: in the headset
# you were in the dark until it finished, which looked like the game had
# broken (and on a Meta Quest, where it is the first thing after opening the
# game, like the game had frozen). A panel in front of you instead: "Loading"
# or "Updating", three moving dots, and what is being loaded.
const VRNotice = preload("res://vr/VRNotice.gd")
var _vr_load: Dictionary = {}
var _vr_t := 0.0
var _vr_away := 0.0
var _vr_posed := false

func _vr_panel():
	_vr_load = VRNotice.make_loading(self)
	_vr_posed = false

func _boot_vr():
	Rhythia.trail("VR at the start (%d ms after the game opened)" % OS.get_ticks_msec())
	if not Rhythia.start_vr_at_boot():
		return # (couldn't: as before, the menu starts VR)
	target = "res://vr/vrmenu.tscn"
	_vr_panel()

func _vr_panel_tick(delta: float):
	_vr_t += delta
	var st: String = $Label2.text if has_node("Label2") else ""
	var updating: bool = st.begins_with("Updating the game")
	_vr_load.title.text = "Updating" if updating else "Loading"
	var detail := st
	if updating:
		# (how far the download is)
		var hr = Online.get("update_hr")
		var total: int = hr.get_body_size() if hr != null else -1
		detail = "Downloading the new version"
		if total > 0:
			detail += "\n%d%%" % int(clamp(100.0 * hr.get_downloaded_bytes() / total, 0, 100))
		detail += "\nIt opens when this is done."
	elif st == "" or st == "Waiting for engine":
		detail = "Reloading content" if Rhythia.first_init_done else "Starting the game"
	_vr_load.detail.text = detail
	for i in range(_vr_load.dots.size()):
		_vr_load.dots[i].modulate.a = 0.25 + 0.75 * max(0.0, sin(_vr_t * 4.0 - i * 0.9))
	# It stays in front of you: put there again when the headset gives its
	# first position, when the view is recentered, and when you've turned
	# away from it for a moment.
	var cam = get_viewport().get_camera()
	if cam == null:
		return
	var has_pose: bool = Rhythia.fake_vr or not (cam.transform.origin == Vector3.ZERO and cam.transform.basis == Basis())
	var off: Array = VRNotice.off_by(_vr_load.mesh, cam)
	_vr_away = _vr_away + delta if off[0] > 55.0 else 0.0
	if (has_pose and not _vr_posed) or off[1] > 0.6 or _vr_away > 0.8:
		VRNotice.place(_vr_load.mesh, cam)
		_vr_posed = _vr_posed or has_pose
		_vr_away = 0.0

var result

func _process(delta):
	if not _vr_load.empty():
		_vr_panel_tick(delta)

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
				get_tree().change_scene("res://scenes/errors/menuload.tscn")

	if leaving and result and black_fade == 1:
		get_tree().change_scene_to(result)
