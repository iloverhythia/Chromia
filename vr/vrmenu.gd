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
	call_deferred("_bake_csg")

# Performance: the pillars are CSG boxes, which keep their CSG machinery (and a
# draw each) around; once built they're turned into plain meshes.
func _bake_csg():
	for holder in [get_node_or_null("Pillers"), get_node_or_null("Pillers2")]:
		if holder == null:
			continue
		for c in holder.get_children():
			if not (c is CSGShape) or not c.is_root_shape():
				continue
			var m: Array = c.get_meshes()
			if m.size() < 2 or m[1] == null:
				continue
			var mi := MeshInstance.new()
			mi.mesh = m[1]
			mi.transform = m[0] # (the CSG node's own transform)
			mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			mi.material_override = c.material_override
			mi.material_overlay = c.material_overlay
			holder.add_child(mi)
			c.queue_free()

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
