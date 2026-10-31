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
	if Rhythia.vr:
		_vr_panel()
	$BlackFade.visible = true
	black_fade = 1
	$BlackFade.color = Color(0, 0, 0, black_fade)
	Rhythia.connect("init_stage_reached", self, "stage")
	var s = Globals.error_sound




	OS.request_permissions()
	if ProjectSettings.get_setting("application/config/auto_maximize") and Rhythia.auto_maximize: OS.window_maximized = true


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
	var vp := Viewport.new()
	vp.size = Vector2(900, 220)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_v_flip = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.08, 1)
	bg.rect_size = vp.size
	vp.add_child(bg)
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = 40
	f.use_filter = true
	_vr_label = Label.new()
	_vr_label.add_font_override("font", f)
	_vr_label.align = Label.ALIGN_CENTER
	_vr_label.valign = Label.VALIGN_CENTER
	_vr_label.autowrap = true
	_vr_label.rect_size = vp.size
	_vr_label.text = "Reloading content..."
	vp.add_child(_vr_label)
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.8 * vp.size.y / vp.size.x)
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_albedo_tex_force_srgb = true
	var tex: ViewportTexture = vp.get_texture()
	tex.flags = Texture.FLAG_FILTER
	m.albedo_texture = tex
	q.material = m
	var mi := MeshInstance.new()
	mi.mesh = q
	add_child(mi)
	# in front of where you're looking, level
	var cam = get_viewport().get_camera()
	var t := Transform()
	if cam:
		var g: Transform = cam.global_transform
		var fwd: Vector3 = -g.basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
		t.origin = g.origin + fwd * 2.4
		t.basis = Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) # (the quad's front, turned to you)
	else:
		t.origin = Vector3(0, 1.6, -2.4)
	mi.global_transform = t

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
