extends CheckBox
# Borderless Windowed: a window one pixel bigger than the screen with no frame,
# so it looks fullscreen but stays an ordinary window (quick Alt-Tab, overlays).
# Exclusive Fullscreen (Fullscreen.gd) is the other kind; only one is on.

func _pressed():
	if pressed != OS.window_borderless:
		Rhythia.set_borderless_windowed(pressed)
	var other = get_parent().get_node_or_null("Fullscreen")
	if other:
		other.pressed = OS.window_fullscreen
	Rhythia.save_settings()

func _ready():
	visible = Rhythia.device("pc")
	pressed = OS.window_borderless
