extends Panel

var open: bool = false
var open_amt: float = 1

onready var pages: Array = [

	get_node("../Main/Maps"),
	get_node("../Main/Settings"),
	get_node("../Main/Credits"),
	get_node("../Main/Content"),
	get_node("../Main/Language"),
	get_node("../Main/UpdateLog"),
	get_node("../Main/Stats"),
	get_node("../Main/Profile"),
	get_node("../Main/Online")
]
onready var buttons: Array = [
	$L/Results,

	$L/Settings,
	$L/Credits,
	$L/ContentMgr,
	$L/Language,
	$L/UpdateLog,
	$L/Stats,
	$L/ProfileTab,
	$L/OnlineTab
]
var use_ver_b: Array = [
	false,

	true,
	false,
	false,
	false,
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
	false,
	false,
	true,
	true
]
onready var smm_visibility: Dictionary = {
	$L/Results: true,

	$L/Settings: true,
	$L/Credits: true,
	$L/ContentMgr: true,
	$L/Language: false,
	$L/UpdateLog: true,
	$L/Stats: true,
	$L/ProfileTab: true,
	$L/OnlineTab: true,
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

func press_page(page: Node):
	var i = pages.find(page)
	if i != -1:
		press(i, true)

func press(bi: int, q: bool = false):
	if bi < 0 or bi >= pages.size():
		return
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
	if Rhythia.device("mobile"):
		# small screens: the label overlaps the pages, and a tapped page
		# shouldn't stay half-covered by the opened sidebar
		get_node("../VersionNumber").visible = false
		get_node("../VersionNumberB").visible = false
		if not q:
			_on_Sidebar(false)




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
	assets.set_large_image(Globals.DISCORD_ICON)
	Discord.activity_manager.update_activity(activity)
	get_viewport().get_node("Menu").black_fade_target = false
	print("done somehow????")

func quit():
	get_node("../Press").play()
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	Rhythia.quit_game()

func _on_vr_status_checked():
	$L/StartVR.visible = Rhythia.vr_available and not Rhythia.vr

# Pages made here rather than in menu2.tscn: a copy of the Online button plus a
# page under Main. Map Browser (download maps from rhythia.com), Map Editor
# (in-game editor, scripts/editor/). Spectate is the eye button (_add_spectate).
func _add_page(node_name: String, script_path: String, icon_path: String, label: String, below: Node) -> Button:
	var main = get_node_or_null("../Main")
	var online_btn = get_node_or_null("L/OnlineTab")
	if main == null or online_btn == null:
		return null
	var page = ReferenceRect.new()
	page.name = node_name
	page.visible = false
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.margin_left = 4.0
	page.margin_top = 4.0
	page.border_color = Color(1, 0, 0, 0)
	page.set_script(load(script_path))
	main.add_child(page)

	var btn: Button = online_btn.duplicate(DUPLICATE_GROUPS | DUPLICATE_SCRIPTS)
	btn.name = node_name + "Tab"
	btn.pressed = false
	$L.add_child_below_node(below if below != null else online_btn, btn)
	btn.get_node("Tex").texture = load(icon_path)
	btn.get_node("Label").text = label

	pages.append(page)
	buttons.append(btn)
	use_ver_b.append(false)
	hide_ver.append(true)
	smm_visibility[btn] = false
	return btn

# (a moment after the menu opens: it picks its first page itself)
func _reopen_spectate():
	yield(get_tree().create_timer(0.3), "timeout")
	if spectate != null and is_inside_tree():
		spectate.open()

# Spectate: the round eye button in the bottom-right corner and the window it
# opens (SpectatePage.gd), on a layer above the menu (under notifications)
var spectate = null
func _add_spectate():
	var layer := CanvasLayer.new()
	layer.name = "SpectateLayer"
	layer.layer = 95
	add_child(layer)
	spectate = Control.new()
	spectate.name = "Spectate"
	spectate.set_script(load("res://scripts/ui/menu/SpectatePage.gd"))
	layer.add_child(spectate)

func _add_extra_pages():
	# the content manager's black backdrop hid the menu background (waves...)
	var cm = get_node_or_null("../Main/Content/Menu")
	if cm is ColorRect:
		cm.color = Color(0, 0, 0, 0)
	var mb = _add_page("MapBrowser", "res://scripts/ui/menu/MapBrowser.gd", "res://assets/images/ui/mapbrowser.png", "Map Browser", null)
	var ed = _add_page("MapEditor", "res://scripts/editor/EditorPage.gd", "res://assets/images/ui/mapeditor.png", "Map Editor", mb)
	# everyone online and what they play, and the global chat: the eye button
	_add_spectate()
	if ed != null and (Rhythia.vr or OS.has_feature("Android") or OS.has_feature("iOS")):
		ed.visible = false # needs a keyboard
	# browser version: a new player has no maps yet; point them to the Map Browser
	if OS.has_feature("JavaScript") and Rhythia.registry_song != null:
		var has_local := false
		for s in Rhythia.registry_song.get_items():
			if not s.is_online:
				has_local = true
				break
		if not has_local:
			Globals.call_deferred("notify", Globals.NOTIFY_INFO, "You don't have any maps yet. Pick an online map in the list to download it, or open the Map Browser (download icon on the left).", "Welcome to Chromia")

func _ready():
	_add_extra_pages()
	Rhythia.trail("menu open")
	PackUpdate.boot_ok() # a downloaded update (iOS) got the game to the menu
	load("res://scripts/PackGuard.gd").ok()
	if OS.get_environment("CHROMIA_BOOT_CHECK") == "1":
		# release check (.github/workflows/release.yml): the game started and got to the menu
		print("CHROMIA_BOOT_OK")
		get_tree().call_deferred("quit")
	load("res://scripts/game/SoundSpaceMode.gd").end_song() # back in the menu: your own settings
	var failed_update = PackUpdate.get("discarded_version")
	if failed_update != null and String(failed_update) != "":
		Globals.call_deferred("notify", Globals.NOTIFY_WARN,
			"Version %s didn't get to the menu on this phone, so Chromia went back to the installed version %s. It will update again when a newer version is out." % [String(failed_update), String(ProjectSettings.get_setting("application/config/version"))],
			"Update removed")
	if Rhythia._pending_update_notice != "":
		Globals.call_deferred("notify", Globals.NOTIFY_SUCCEED,
			("Version %s is downloaded. Quit Chromia (Meta button, then Quit) and open it again to use it." if OS.has_feature("quest") else
			"Version %s is downloaded. Close Chromia completely (swipe it away in the app switcher) and open it again to use it.") % Rhythia._pending_update_notice,
			"Update ready")
		Rhythia._pending_update_notice = ""
	# test builds: scores go to the test server, never the real leaderboards
	# (once per session, the first time the menu opens)
	if Online.build_channel() == "test" and not Rhythia.has_meta("test_build_warned"):
		Rhythia.set_meta("test_build_warned", true)
		Globals.call_deferred("notify", Globals.NOTIFY_WARN,
			"This is a test build: your scores, XP and SP go to the TEST leaderboards, not the real ones (and they get wiped now and then). For scores that count, switch to Stable in Settings > Check for Updates.",
			"Test build", 12.0)
	# (Quest: shown once the VR menu is up; the first, flat menu isn't visible)
	if (Rhythia.last_session_crashed or (Rhythia.always_show_crash_log and Rhythia.last_session_trail.strip_edges() != "")) and not Rhythia.crash_report_shown and (Rhythia.vr or not OS.has_feature("quest")):
		Rhythia.crash_report_shown = true
		call_deferred("_show_crash_report")
	for i in range(buttons.size()):
		buttons[i].connect("pressed", self, "press", [i])

	press(0, true)
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null and lm.reopen_spectate_tab:
		lm.reopen_spectate_tab = false # back from watching someone: pick the next
		call_deferred("_reopen_spectate")
	$Click.connect("mouse_entered", self, "_on_Sidebar", [true])
	if Rhythia.device("mobile"):
		$Click.visible = false # touch: a tap on an icon opens that page right away
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
	# Stats is a tab in the profile panel and Language is a settings tab now.
	$L/Stats.visible = false
	$L/Language.visible = false

	refresh_language_labels()
	# Meta Quest app: straight into VR (there's no flat screen to see)
	if OS.has_feature("quest") and not Rhythia.vr:
		Rhythia.call_deferred("start_vr")

func _process(delta: float):
	if open and not Rect2(get_global_rect()).has_point(Rhythia.menu_mouse(self)):
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
		get_node("Click").visible = not open and not Rhythia.device("mobile")
		get_node("../SidebarClick").visible = open

	if Input.is_action_just_pressed("ui_quicksettings") and not _typing():
		press(1)

	if Input.is_action_just_pressed("menu_quickbar"):
		open = true
		get_node("Click").visible = not open and not Rhythia.device("mobile")

# True while a text box has focus (or the map editor is open), so typing an "o"
# doesn't jump to Settings.
func _typing() -> bool:
	var f = get_focus_owner()
	if f is LineEdit or f is TextEdit:
		return true
	var ed = get_node_or_null("../Main/MapEditor")
	return ed != null and ed.visible

func _on_Sidebar(isEntered: bool):
	open = isEntered
	get_node("Click").visible = not open and not Rhythia.device("mobile")
	get_node("../SidebarClick").visible = open


# The last session ended without closing normally: show what it was doing
# (Rhythia's crash trail) and offer to copy it for a bug report.
func _show_crash_report():
	yield(get_tree().create_timer(1.5), "timeout")
	if not is_inside_tree() or Globals.confirm_prompt == null:
		return
	var last := Array(Rhythia.last_session_trail.strip_edges().split("\n"))
	var shown := []
	for i in range(max(0, last.size() - 6), last.size()):
		# drop the [time | objs | vram] prefix to keep the box short
		var l := String(last[i])
		var cut := l.find("] ")
		shown.append(l.substr(cut + 2) if cut != -1 else l)
	var crashed: bool = Rhythia.last_session_crashed
	Globals.confirm_prompt.open(
		("Chromia closed unexpectedly last time. The last things it did:\n\n%s\n\nTap Copy report and send it to the developer." if crashed else
		"Last session's log (Settings > Replays & Misc > Experimental shows this every start). The last things it did:\n\n%s") % PoolStringArray(shown).join("\n"),
		"Chromia crashed" if crashed else "Last session",
		[{text = "OK"}, {text = "Copy report"}]
	)
	var picked = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if picked == 1:
		OS.clipboard = Rhythia.crash_report()
		Globals.notify(Globals.NOTIFY_SUCCEED, "The crash report is copied. Paste it in a message to the developer.", "Copied")
