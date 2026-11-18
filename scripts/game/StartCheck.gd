extends Node

# What a song is played with, written to the trail once when it starts, and
# what came of the first seconds: did the mouse (or a controller) move, did
# the cursor follow, were the HUD's panels drawn. For reports of a map that
# doesn't work on one computer ("the cursor doesn't move", "half the HUD is
# missing") that can't be seen anywhere else: the log says what that computer
# did. Game.gd adds it when a song starts; it removes itself after CHECK_S.

const CHECK_S := 6.0

var _t := 0.0
var _mouse_n := 0
var _mouse_px := 0.0
var _pad_n := 0
var _pad_axes := {}
var _cursor: Spatial = null
var _cursor_from := Vector2.ZERO
var _cursor_far := 0.0
var _hud: Node = null

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	var game = get_parent()
	_cursor = game.get_node_or_null("Spawn/Cursor")
	_hud = game.get_node_or_null("HUD")
	if _cursor != null and "rpos" in _cursor:
		_cursor_from = _cursor.rpos
	Rhythia.trail("song start: " + _facts(), false)

static func _yn(v) -> String:
	return "on" if bool(v) else "off"

func _facts() -> String:
	var vp: Viewport = get_viewport()
	var win: Vector2 = OS.get_window_size()
	var pads := []
	for id in Input.get_connected_joypads():
		pads.append(Input.get_joy_name(id).left(40))
	var mods := []
	for m in ["nofail", "hardrock", "harderrock", "mirror_x", "mirror_y", "ghost", "flashlight", "true_flashlight", "nearsighted", "chaos", "earthquake", "360", "reverse", "hard_mode"]:
		if bool(Rhythia.get("mod_" + m)):
			mods.append(m)
	return "window %d x %d%s, drawn %d x %d (render resolution %s, x%s, screen scale %s), mouse: %s, sensitivity %s%s%s%s, controllers: %s%s | hud: font %s, panels %s%s%s%s%s%s, cursor bloom %s | mods: %s" % [
		int(win.x), int(win.y), " fullscreen" if OS.window_fullscreen else "",
		int(vp.size.x), int(vp.size.y),
		"auto" if int(Rhythia.render_res) <= 0 else "%d%%" % int(Rhythia.render_res), str(Rhythia.render_shrink), str(OS.get_screen_scale()),
		"absolute" if Rhythia.absolute_mode else "relative", str(Rhythia.sensitivity),
		", spin" if Rhythia.spin_now() else "", ", legacy" if bool(Rhythia.get("legacy_mouse")) else "", ", inverted" if Rhythia.invert_mouse else "",
		str(pads) if not pads.empty() else "none", " (ignored)" if Rhythia.ignore_controller_detection else "",
		String(Rhythia.get("hud_font")), load("res://scripts/HudPanels.gd").current(),
		"" if Rhythia.show_timer else ", no timer", "" if Rhythia.show_left_panel else ", no left panel", "" if Rhythia.show_right_panel else ", no right panel",
		", simple" if Rhythia.simple_hud else "", ", faraway" if Rhythia.faraway_hud else "",
		_yn(Rhythia.get("cursor_glow")),
		PoolStringArray(mods).join(" ") if not mods.empty() else "none"]

func _input(event: InputEvent):
	if event is InputEventMouseMotion:
		_mouse_n += 1
		_mouse_px += Rhythia.mouse_rel(event).length()
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		_pad_n += 1
		_pad_axes[event.axis] = true

func _process(delta: float):
	_t += delta
	if is_instance_valid(_cursor) and "rpos" in _cursor:
		_cursor_far = max(_cursor_far, (_cursor.rpos - _cursor_from).length())
	if _t < CHECK_S:
		return
	set_process(false)
	var panels := []
	if is_instance_valid(_hud):
		for n in ["Timer", "Left", "Right"]:
			var v = _hud.get_node_or_null(n + "VP")
			var c = v.get_node_or_null("Control") if v != null else null
			var shown = _hud.get_node_or_null(n + "Hud")
			if shown == null: # (moved onto the grid: attach to grid)
				shown = get_parent().get_node_or_null("Spawn/" + n + "Hud")
			panels.append("%s %s%s%s" % [n.to_lower(),
				("%d x %d" % [int(v.size.x), int(v.size.y)]) if v is Viewport else "?",
				(" (laid out %d x %d)" % [int(c.rect_size.x), int(c.rect_size.y)]) if c is Control and v is Viewport and c.rect_size != v.size else "",
				"" if shown is Spatial and shown.is_visible_in_tree() else " hidden"])
	var mode := "?"
	if is_instance_valid(_cursor) and "move_mode" in _cursor:
		mode = "controller" if int(_cursor.move_mode) == 1 else "mouse"
	Rhythia.trail("first %d s: the mouse moved %d times (%d px), controller %d times%s; cursor moved by the %s, %s; mouse mode %d; panels: %s; %d fps" % [
		int(CHECK_S), _mouse_n, int(_mouse_px), _pad_n,
		(" (axes %s)" % str(_pad_axes.keys())) if _pad_n > 0 else "",
		mode,
		("went %.2f from where it started" % _cursor_far) if is_instance_valid(_cursor) else "gone",
		Input.get_mouse_mode(), PoolStringArray(panels).join(", "), int(Engine.get_frames_per_second())], false)
	queue_free()
