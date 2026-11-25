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
	# Render Resolution, under these (scripts/ui/settings/RenderRes.gd)
	call_deferred("_add_render_res")

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
	cb.hint_tooltip = "Removes mouse movement delay in maps: every mouse movement is used as soon as it comes in, even while a frame is being made, and VSync and the Windows compositor's extra frame are off while you play (yours come back after the map). Frames are held to four times your screen's refresh rate (240 to 1,000 a second, or your Max FPS if lower), so the graphics card isn't so full that the picture stutters. PC only. Uses more GPU."
	p.add_child(cb)
	p.move_child(cb, get_index() + 1)
	cb.pressed = Rhythia.pc_no_delay

func _add_render_res():
	load("res://scripts/ui/settings/RenderRes.gd").attach(self)
	_add_menu_limit()

# Limit FPS in Menus (scripts/StreamMode.gd), computers only
func _add_menu_limit():
	var p = get_parent()
	if p == null or p.has_node("MenuFpsLimit") or Rhythia.device("mobile") or OS.has_feature("JavaScript") or OS.has_feature("quest"):
		return
	var cb: CheckBox = duplicate(0)
	cb.name = "MenuFpsLimit"
	cb.set_script(load("res://scripts/ui/settings/SettingsCheckbox.gd"))
	cb.target = "menu_fps_limit"
	cb.text = "Limit FPS in Menus"
	cb.hint_tooltip = "In the menus the game draws as often as your screen shows (144 times a second at most), and 30 times a second while its window isn't in front, instead of as often as the graphics card can. On a fast card that is a few percent of it instead of nearly all, with less heat and fan noise and more room for a stream or a recording.\nMaps aren't touched: there it's your Max FPS, or no limit. Off: no limit in the menus either."
	p.add_child(cb)
	p.move_child(cb, get_index() + 1)
	cb.pressed = Rhythia.menu_fps_limit
