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
	call_deferred("_add_no_delay")

# Experimental: No Delay (PC mouse, Savia.no_delay_begin), right under this one
func _add_no_delay():
	var p = get_parent()
	if p == null or p.has_node("PCNoDelay") or Rhythia.device("mobile") or OS.has_feature("JavaScript"):
		return
	var cb: CheckBox = duplicate(0)
	cb.name = "PCNoDelay"
	cb.set_script(load("res://scripts/ui/settings/SettingsCheckbox.gd"))
	cb.target = "pc_no_delay"
	cb.text = "No Delay (Experimental)"
	cb.hint_tooltip = "Removes mouse movement delay in maps: every mouse movement is used as soon as it comes in, even while a frame is being made, and VSync, the FPS cap and the Windows compositor's extra frame are off while you play (yours come back after the map). PC only. Uses more GPU."
	p.add_child(cb)
	p.move_child(cb, get_index() + 1)
	cb.pressed = Rhythia.pc_no_delay
