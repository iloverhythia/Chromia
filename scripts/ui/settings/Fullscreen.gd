extends CheckBox
# "Fullscreen": the engine's fullscreen, a window exactly the size of the
# screen with nothing around it, which the graphics driver runs on its own
# (lowest input delay; Alt-Tab is slower). Borderless Windowed
# (BorderlessWindowed.gd) is the other kind: one pixel bigger than the screen,
# so it stays an ordinary window. Only one is on at a time.

func _pressed():
	if Rhythia.vr:
		pressed = OS.window_fullscreen # (the window stays as it is in VR: a change left the headset black)
		return
	if pressed and OS.window_borderless:
		Rhythia.set_borderless_windowed(false)
	if pressed != OS.window_fullscreen:
		OS.window_fullscreen = pressed
	sync_all(get_parent())
	Rhythia.save_settings()

# both boxes show the window as it is
static func sync_all(parent: Node):
	if parent == null:
		return
	var fs = parent.get_node_or_null("Fullscreen")
	if fs:
		fs.pressed = OS.window_fullscreen
	var bw = parent.get_node_or_null("Borderless Windowed")
	if bw:
		bw.pressed = OS.window_borderless and not OS.window_fullscreen

func _sync():
	sync_all(get_parent())

func _ready():
	visible = Rhythia.device("pc") or OS.has_feature("JavaScript")
	pressed = OS.window_fullscreen
	connect("visibility_changed", self, "_sync")
