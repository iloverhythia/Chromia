extends CheckBox
# Borderless Windowed: a window one pixel bigger than the screen with no frame,
# so it looks fullscreen but stays an ordinary window (quick Alt-Tab, overlays).
# Exclusive Fullscreen (Fullscreen.gd) and Fullscreen (FullscreenNormal.gd)
# are the other kinds; only one is on.

func _pressed():
	var on: bool = OS.window_borderless and not Rhythia.normal_fullscreen and not OS.window_fullscreen
	if pressed != on:
		Rhythia.set_borderless_windowed(pressed)
	load("res://scripts/ui/settings/Fullscreen.gd").sync_all(get_parent())
	Rhythia.save_settings()

func _ready():
	visible = Rhythia.device("pc")
	pressed = OS.window_borderless and not Rhythia.normal_fullscreen
