extends Reference
# Settings > Background Editor > Background brightness: a dark, see-through
# sheet just in front of each camera in songs. It's drawn first of the
# see-through things, right after the solid background, so the world behind
# goes darker while the notes, cursor, grid and HUD (all drawn after it) stay
# as bright as ever.

const NAME := "BgVeil"

static func amount() -> float:
	var v = Rhythia.get("bg_brightness")
	return 1.0 - clamp(float(v) / 100.0, 0.0, 1.0) if v != null else 0.0

static func add_to(cam: Spatial):
	if cam == null or not is_instance_valid(cam):
		return
	var old = cam.get_node_or_null(NAME)
	if old:
		old.queue_free()
	var a := amount()
	if a <= 0.001:
		return
	var q := QuadMesh.new()
	q.size = Vector2(4, 4) # (covers the view at this distance even at very wide FOVs)
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.flags_no_depth_test = true
	m.flags_do_not_receive_shadows = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.albedo_color = Color(0, 0, 0, a)
	m.render_priority = Material.RENDER_PRIORITY_MIN
	var mi := MeshInstance.new()
	mi.name = NAME
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.transform.origin = Vector3(0, 0, -0.12)
	cam.add_child(mi)

static func remove_from(cam: Spatial):
	if cam != null and is_instance_valid(cam):
		var old = cam.get_node_or_null(NAME)
		if old:
			old.queue_free()
