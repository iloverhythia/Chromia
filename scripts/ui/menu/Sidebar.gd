extends Panel

var open: bool = false
var open_amt: float = 1

onready var pages: Array = [

	get_node("../Main/Maps"),
	get_node("../Main/Settings"),
	get_node("../Main/Credits"),
	get_node("../Main/Content"),
	get_node("../Main/Language"),
	get_node("../Main/UpdateLog")
]
onready var buttons: Array = [
	$L/Results,

	$L/Settings,
	$L/Credits,
	$L/ContentMgr,
	$L/Language,
	$L/UpdateLog
]
var use_ver_b: Array = [
	false,

	true,
	false,
	false,
	false,
	false
]
var hide_ver: Array = [
	false,

	false,
	true,
	false,
	false,
	false
]
onready var smm_visibility: Dictionary = {
	$L/Results: true,

	$L/Settings: true,
	$L/Credits: true,
	$L/ContentMgr: true,
	$L/Language: false,
	$L/UpdateLog: true,
	$L/StartVR: false,
	$L/OldMenu: false,
	$L/Quit: true,
}

const DYV_LABELS: Array = [
	"Dude Your Voice",
	"That's Not Me",
	"Can Someone Grab Bomb",
	"Can You Shut The F-ck Up",
	"Shut The F-ck Up",
	"You're doing nothing for the team!",
	"SHUT THE F-CK UP YOU'RE DOING NOTHING FOR THE TEAM"
]
var _default_labels: Array = []

func refresh_language_labels():
	if _default_labels.empty():
		for b in buttons:
			_default_labels.append(b.get_node("Label").text)
	var dyv: bool = Rhythia.language == Globals.LANGUAGE_DUDE_YOUR_VOICE
	for i in range(buttons.size()):
		var lbl = buttons[i].get_node("Label")
		lbl.text = DYV_LABELS[i] if dyv and i < DYV_LABELS.size() else _default_labels[i]

func press(bi: int, q: bool = false):
	if not q: get_node("../Press").play()
	for i in range(pages.size()):
		pages[i].visible = i == bi
		buttons[i].pressed = i == bi
	yield(get_tree(), "idle_frame")

	get_node("../VersionNumber").visible = not use_ver_b[bi]
	get_node("../VersionNumberB").visible = use_ver_b[bi]
	if (hide_ver[bi]):
		get_node("../VersionNumber").self_modulate = Color(1, 1, 1, 0)
	else:
		get_node("../VersionNumber").self_modulate = Color(1, 1, 1, 1)




func to_old_menu():
	get_node("../Press").play()
	get_viewport().get_node("Menu").black_fade_target = true
	if Input.is_key_pressed(KEY_C):
		if not Rhythia.selected_song:
			Globals.notify(Globals.NOTIFY_WARN, "No selected song", "Automatically selecting a song")
			Rhythia.select_song(Rhythia.registry_song.items[0])
		Rhythia.menu_target = "res://scripts/cursordance/dancetest.tscn"
	else: Rhythia.menu_target = "res://scenes/menu/menu.tscn"
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func to_vr():
	if OS.has_feature("HTML5"): return
	get_node("../Press").play()
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	print("will now try to play in vr")
	Rhythia.start_vr()
	var activity = Discord.Activity.new()
	activity.set_type(Discord.ActivityType.Playing)
	activity.set_details("Loaded VR (test)")
	activity.set_state("savvying it in vr!")
	var assets = activity.get_assets()
	assets.set_large_image("icon-bg")
	Discord.activity_manager.update_activity(activity)
	get_viewport().get_node("Menu").black_fade_target = false
	print("done somehow????")

func quit():
	get_node("../Press").play()
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().quit()

func _on_vr_status_checked():
	$L/StartVR.visible = Rhythia.vr_available and not Rhythia.vr

func _ready():
	for i in range(buttons.size()):
		buttons[i].connect("pressed", self, "press", [i])

	press(0, true)
	if Rhythia.vr:
		$Click.connect("vr_click", self, "_on_Sidebar", [true])
		$L.connect("vr_click", self, "_on_Sidebar", [true])
	$Click.connect("mouse_entered", self, "_on_Sidebar", [true])
	$L.connect("mouse_entered", self, "_on_Sidebar", [true])
	connect("mouse_exited", self, "_on_Sidebar", [false])
	$L/OldMenu.connect("pressed", self, "to_old_menu")
	$L/StartVR.connect("pressed", self, "to_vr")
	$L/Quit.connect("pressed", self, "quit")

	$L/ContentMgr.visible = not Rhythia.vr
	$L/StartVR.visible = Rhythia.vr_available and not Rhythia.vr
	Rhythia.connect("vr_status_checked", self, "_on_vr_status_checked")
	Rhythia.ensure_vr_checked()
	if Rhythia.vr or not OS.has_feature("pc"):
		$L/Quit/Label.text = "Quit to Home"

	if Rhythia.single_map_mode:
		for n in $L.get_children():
			n.visible = smm_visibility.get(n, false)

	refresh_language_labels()

func _process(delta: float):
	if open and not Rect2(get_global_rect()).has_point(get_global_mouse_position()):
		_on_Sidebar(false)

	if open == true and open_amt != 1:
		open_amt = min(open_amt + max((1 - open_amt) * delta * 14, 0.05 * delta), 1)

	elif open == false and open_amt != 0:
		open_amt = max(open_amt + min((0 - open_amt) * delta * 12, -0.05 * delta), 0)


	rect_size.x = 60 + (180 * open_amt)

func _input(ev):
	if (ev is InputEventScreenTouch or ev is InputEventMouseButton):
		if ev.pressed != true: return
		open = ev.position.x < rect_size.x and ev.position.y < rect_size.y
		yield(get_tree(), "idle_frame")
		get_node("Click").visible = not open
		get_node("../SidebarClick").visible = open

	if Input.is_action_just_pressed("ui_quicksettings"):
		press(1)

	if Input.is_action_just_pressed("menu_quickbar"):
		open = true
		get_node("Click").visible = not open

func _on_Sidebar(isEntered: bool):
	open = isEntered
	get_node("Click").visible = not open
	get_node("../SidebarClick").visible = open
