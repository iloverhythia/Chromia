extends CheckBox
# "Exclusive Fullscreen": the engine's fullscreen, a window exactly the size of
# the screen with nothing around it, which the graphics driver runs as
# exclusive fullscreen (lowest input delay; Alt-Tab is slower).
# "Fullscreen" (FullscreenNormal.gd, added next to it from here) fills the
# screen the game is on but stays an ordinary window (quick Alt-Tab,
# overlays). Borderless Windowed (BorderlessWindowed.gd) is a frameless
# window over the main screen. Only one of the three is on at a time.

func _pressed():
	if pressed:
		if Rhythia.normal_fullscreen:
			Rhythia.set_normal_fullscreen(false)
		if OS.window_borderless:
			Rhythia.set_borderless_windowed(false)
	if pressed != OS.window_fullscreen:
		OS.window_fullscreen = pressed
	sync_all(get_parent())
	Rhythia.save_settings()

# the three boxes show the window as it is
static func sync_all(parent: Node):
	if parent == null:
		return
	var ex = parent.get_node_or_null("Fullscreen")
	if ex:
		ex.pressed = OS.window_fullscreen
	var nf = parent.get_node_or_null("NormalFullscreen")
	if nf:
		nf.pressed = Rhythia.normal_fullscreen and not OS.window_fullscreen
	var bw = parent.get_node_or_null("Borderless Windowed")
	if bw:
		bw.pressed = OS.window_borderless and not Rhythia.normal_fullscreen and not OS.window_fullscreen

func _sync():
	sync_all(get_parent())

func _ready():
	visible = Rhythia.device("pc") or OS.has_feature("JavaScript")
	pressed = OS.window_fullscreen
	connect("visibility_changed", self, "_sync")
	if Rhythia.device("pc") and not OS.has_feature("JavaScript"):
		call_deferred("_add_normal")

func _add_normal():
	var parent = get_parent()
	if parent == null or parent.has_node("NormalFullscreen"):
		return
	var cb: CheckBox = duplicate()
	cb.set_script(load("res://scripts/ui/settings/FullscreenNormal.gd"))
	cb.name = "NormalFullscreen"
	cb.text = "Fullscreen"
	cb.hint_tooltip = "Fills the screen the game is on, with no frame, but stays an ordinary window: Alt-Tab is quick and overlays work. Exclusive Fullscreen is the one your graphics driver runs on its own (lowest input delay)."
	parent.add_child(cb)
	parent.move_child(cb, get_index())
	_sync()
