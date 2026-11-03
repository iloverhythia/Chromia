extends CheckBox
# "Exclusive Fullscreen": the engine's fullscreen, a window exactly the size of
# the screen with nothing around it, which the graphics driver runs as
# exclusive fullscreen (lowest input delay; Alt-Tab is slower). Borderless
# Windowed (BorderlessWindowed.gd) is the other kind: one pixel bigger than
# the screen, so it stays an ordinary window. Only one is on at a time.

func _pressed():
	if pressed and OS.window_borderless:
		Rhythia.set_borderless_windowed(false)
	if pressed != OS.window_fullscreen:
		OS.window_fullscreen = pressed
	_sync()
	Rhythia.save_settings()

func _sync():
	pressed = OS.window_fullscreen
	var other = get_parent().get_node_or_null("Borderless Windowed")
	if other:
		other.pressed = OS.window_borderless

func _ready():
	visible = Rhythia.device("pc") or OS.has_feature("JavaScript")
	pressed = OS.window_fullscreen
	connect("visibility_changed", self, "_sync")
