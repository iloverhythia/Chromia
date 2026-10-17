extends CheckBox

# One switch for the highest frame rate: no FPS cap, no VSync, no MSAA.
func _pressed():
	Rhythia.max_fps_mode = pressed
	Rhythia.apply_max_fps_mode()
	var vs = get_parent().get_node_or_null("VSync")
	if vs: vs.pressed = OS.vsync_enabled

func _ready():
	pressed = Rhythia.max_fps_mode
