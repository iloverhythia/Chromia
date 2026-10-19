extends CheckBox

# One switch for the highest frame rate: no FPS cap, no VSync, no MSAA.
func _pressed():
	Rhythia.max_fps_mode = pressed
	Rhythia.apply_max_fps_mode()
	var vs = get_parent().get_node_or_null("VSync")
	if vs: vs.pressed = OS.vsync_enabled
	# the FPS Limit box puts its own value back into Engine.target_fps every
	# frame, so show the removed cap there too or the cap comes right back
	var fps_box = get_parent().get_node_or_null("TargetFPS/Sensitivity")
	if fps_box: fps_box.value = Engine.target_fps

func _ready():
	pressed = Rhythia.max_fps_mode
