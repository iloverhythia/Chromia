extends Node

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
		if not Rhythia.vr:
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

# In VR this loading screen (Reload Content) is only on the computer's window:
# in the headset you were in the dark until it finished, which looked like the
# game had broken. The same text on a panel in front of you instead.
var _vr_label: Label = null

func _vr_panel():
	_vr_label = load("res://vr/VRNotice.gd").make(self, "Reloading content...")

var result

func _process(delta):
	if _vr_label and has_node("Label2"):
		_vr_label.text = $Label2.text if $Label2.text != "" else "Reloading content..."

	$Music.volume_db = -8 - (40 * black_fade)
	if black_fade_target and black_fade != 1:
		black_fade = min(black_fade + (delta / 0.3), 1)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	elif not black_fade_target and black_fade != 0:
		black_fade = max(black_fade - (delta / 0.3), 0)
		$BlackFade.color = Color(0, 0, 0, black_fade)

	if not leaving:
		if RQueue.is_ready(target):
			result = RQueue.get_resource(target)
			leaving = true
			black_fade_target = true
			if not (result is Object):
				Rhythia.errorstr = "get_resource returned non-object (probably null)"
				get_tree().change_scene("res://scenes/errors/menuload.tscn")

	if leaving and result and black_fade == 1:
		get_tree().change_scene_to(result)
