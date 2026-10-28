extends Spatial

# The VR menu: the normal menu drawn on a screen floating in front of you
# (PointerScreen, pointed at with the controller, see MenuPointer.gd).
#
# The game's boxes and messages (confirm boxes, text prompts, the file picker,
# notifications) normally sit on the flat window, which you can't see in the
# headset. While this menu is up they're moved onto its screen (with the VR
# keyboard, VRKeyboard.gd), and back to the window when it goes.

func _ready():
	Rhythia.vr_menu = $PointerScreen # VRPlayer.recenter_to_head puts it back in front of you
	$PointerScreen.set_meta("home", $PointerScreen.transform)
	call_deferred("_adopt_overlays")
	_classic_env = $WorldEnvironment.environment
	# a background as the menu environment, and the game crashed last time:
	# the classic room this time, in case that background was the cause
	if Rhythia.vr_menu_env.begins_with("bg:") and Rhythia.last_session_crashed and not Rhythia.has_meta("vr_env_crash_checked"):
		Rhythia.set_meta("vr_env_crash_checked", true)
		Rhythia.trail("VR menu: the last session crashed, classic environment instead of " + Rhythia.vr_menu_env)
		Rhythia.vr_menu_env = "classic"
		Globals.call_deferred("notify", Globals.NOTIFY_INFO, "The game closed unexpectedly last time, so the menu is in the Classic environment. Pick your background again in Settings > VR if you like.", "VR menu")
	apply_env()


# --- What's around you (Settings > VR > Menu environment, vr/MenuEnvs.gd) ---
# "classic" is this scene's own room (the logo and the floating avatar);
# anything else is built by MenuEnvs and put in its place.
var _classic_env: Environment = null
const CLASSIC_NODES := ["Sprite3D", "Sprite3D2", "Sprite3D3", "Avatar"]

func apply_env():
	var old = get_node_or_null("MenuEnv")
	if old != null:
		remove_child(old) # (its WorldEnvironment lets go of the world now)
		old.queue_free()
	var env = load("res://vr/MenuEnvs.gd").make(Rhythia.vr_menu_env)
	var classic: bool = env == null
	for n in CLASSIC_NODES:
		var c = get_node_or_null(n)
		if c != null:
			c.visible = classic
	# one WorldEnvironment at a time: the classic one steps aside
	$WorldEnvironment.environment = _classic_env if classic else null
	if env != null:
		add_child(env)
	Rhythia.trail("VR menu environment: %s" % (Rhythia.vr_menu_env if env != null else "classic"))

func _overlays() -> Array:
	var out := []
	for n in [Globals.notify_gui.get_parent() if Globals.notify_gui else null, Globals.confirm_prompt, Globals.string_prompt, Globals.file_sel]:
		if n != null and is_instance_valid(n) and n.is_inside_tree():
			out.append(n)
	return out

func _adopt_overlays():
	var vp: Viewport = $PointerScreen/Viewport
	# Freed first when this scene goes (a node's children are freed last to
	# first, before its own scripts hear about it): gives the boxes back.
	var guard := OverlayGuard.new()
	guard.name = "OverlayGuard"
	add_child(guard)
	for n in _overlays():
		var old = n.get_parent()
		if old == vp:
			continue
		old.remove_child(n)
		vp.add_child(n)
		guard.moved.append([n, old])
	if not vp.has_node("VRKeyboard"):
		var kb = load("res://vr/VRKeyboard.gd").new()
		kb.name = "VRKeyboard"
		vp.add_child(kb)

class OverlayGuard extends Node:
	var moved := [] # [node, its old parent]
	func _notification(what):
		if what != NOTIFICATION_PREDELETE:
			return
		for m in moved:
			var n = m[0]
			var old = m[1]
			if is_instance_valid(n) and is_instance_valid(old):
				if n.get_parent():
					n.get_parent().remove_child(n)
				old.add_child(n)
		moved.clear()
