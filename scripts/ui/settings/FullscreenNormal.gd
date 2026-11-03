extends CheckBox
# "Fullscreen" (Settings > Video & Audio): the game fills the screen it's on
# with no frame, one pixel taller than the screen so the graphics driver keeps
# it an ordinary window (quick Alt-Tab, overlays, the other screens stay
# usable). Exclusive Fullscreen and Borderless Windowed turn it off.
# Fullscreen.gd adds this box next to Exclusive Fullscreen.

func _pressed():
	if pressed != Rhythia.normal_fullscreen:
		Rhythia.set_normal_fullscreen(pressed)
	load("res://scripts/ui/settings/Fullscreen.gd").sync_all(get_parent())
	Rhythia.save_settings()

func _ready():
	visible = Rhythia.device("pc") and not OS.has_feature("JavaScript")
	pressed = Rhythia.normal_fullscreen and not OS.window_fullscreen
