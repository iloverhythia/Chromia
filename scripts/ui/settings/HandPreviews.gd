extends Reference

# Pictures of the VR hands for the Hands picker (Settings > VR > Hands, shown
# in WorldPicker.gd like the backgrounds): each hand is drawn once into a
# small Viewport of its own, and the tile shows that Viewport's picture.

const SIZE := Vector2(256, 192) # (the picker's tiles are 4:3)

# kind ("default", "paw", ... as Rhythia.vr_hand) -> [mesh, Transform, material for surfaces without one] or null
static func model_of(kind: String):
	var t := Transform()
	match kind:
		"default":
			return _default_hand()
		"paw":
			return [load("res://vr/PawHand.gd").build(), t, null]
		"ball":
			return [load("res://vr/BallHand.gd").build(), t, null]
		"snowleopard":
			return [load("res://vr/SnowLeopardPaw.gd").build(), t, null]
		"built":
			var HC = load("res://vr/HandCreator.gd")
			var design = Rhythia.vr_hand_design
			if design == null or design.empty():
				design = HC.PRESETS[0][1]
			return [HC.build(design), t, null]
		"custom":
			var path: String = Globals.p("user://vr_hand.obj")
			if not File.new().file_exists(path):
				return null
			var m = load("res://scripts/content/resources/ObjParse.gd").load_obj(path)
			if m == null or m.get_surface_count() == 0:
				return null
			return [m, t, _plain()]
	if load("res://vr/ExtraHands.gd").has(kind):
		return [load("res://vr/ExtraHands.gd").build(kind), t, null]
	return null

# the plain hand (VRPlayer.tscn's right hand: its mesh, place and look)
static func _default_hand():
	var st: SceneState = load("res://vr/VRPlayer.tscn").get_state()
	for i in range(st.get_node_count()):
		var path := str(st.get_node_path(i))
		if path.trim_prefix("./") != "Origin/RightHand/Mesh":
			continue
		var mesh = null
		var t := Transform()
		var mat = null
		for k in range(st.get_node_property_count(i)):
			match st.get_node_property_name(i, k):
				"mesh": mesh = st.get_node_property_value(i, k)
				"transform": t = st.get_node_property_value(i, k)
				"material/0": mat = st.get_node_property_value(i, k)
		if mesh != null:
			return [mesh, t, mat if mat != null else _plain()]
	return null

static func _plain() -> Material:
	var m := SpatialMaterial.new()
	m.albedo_color = Color(0.92, 0.9, 1.0)
	return m

# hands that take a while to make (about a second on a PC): drawn a moment after
# the picker shows (VRTab._fill_hand_previews), and kept for the next time
const SLOW := ["paw", "snowleopard"]
# (the ones that don't change: kept while the game runs)
const KEEP := ["default", "paw", "ball", "glove", "robot", "skeleton", "crystal", "snowleopard"]

static func cached_model(kind: String):
	var cache: Dictionary = Engine.get_meta("hand_preview_models") if Engine.has_meta("hand_preview_models") else {}
	if cache.has(kind):
		return cache[kind]
	var model = null
	# (the hand you have on is already made)
	var vrp = Rhythia.vr_player
	if kind in SLOW and vrp != null and is_instance_valid(vrp) and str(vrp.get("_hand_shown")) == kind and vrp._hand_default.size() > 1:
		var mi = vrp._hand_default[1][0]
		if is_instance_valid(mi) and mi.mesh != null:
			model = [mi.mesh, Transform(), null]
	if model == null:
		model = model_of(kind)
	if kind in KEEP and model != null:
		cache[kind] = model
		Engine.set_meta("hand_preview_models", cache)
	return model

static func is_ready(kind: String) -> bool:
	return not (kind in SLOW) or (Engine.has_meta("hand_preview_models") and Engine.get_meta("hand_preview_models").has(kind))

# a Viewport for one hand's picture (empty until fill()); add it to the tree
# (anywhere) and use its get_texture()
static func make_viewport() -> Viewport:
	var vp := Viewport.new()
	vp.own_world = true
	vp.size = SIZE
	vp.msaa = Viewport.MSAA_4X
	vp.transparent_bg = false
	vp.render_target_v_flip = true
	vp.render_target_update_mode = Viewport.UPDATE_ONCE
	vp.usage = Viewport.USAGE_3D
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.085, 0.12)
	env.ambient_light_color = Color(0.55, 0.52, 0.62)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight.new()
	vp.add_child(light)
	light.look_at_from_position(Vector3(0.4, 1.0, 0.7), Vector3.ZERO, Vector3.UP)
	var mi := MeshInstance.new()
	mi.name = "Hand"
	vp.add_child(mi)
	var cam := Camera.new()
	cam.name = "Cam"
	cam.fov = 40
	cam.near = 0.005
	cam.far = 10.0
	vp.add_child(cam)
	cam.current = true
	return vp

# draws the hand into the Viewport (once). false: there is no such hand to draw
static func fill(vp: Viewport, kind: String) -> bool:
	var model = cached_model(kind)
	if model == null or model[0] == null or not is_instance_valid(vp):
		return false
	var mesh: Mesh = model[0]
	var mi: MeshInstance = vp.get_node("Hand")
	mi.mesh = mesh
	mi.transform = model[1]
	for k in range(mesh.get_surface_count()):
		mi.set_surface_material(k, model[2] if mesh.surface_get_material(k) == null else null)
	# the camera behind and above the hand (its fingers point away, along -Z),
	# just far enough back that the whole hand fits
	var box: AABB = mi.transform.xform(mesh.get_aabb())
	var c: Vector3 = box.position + box.size * 0.5
	var r: float = max(0.02, box.size.length() * 0.5)
	var cam: Camera = vp.get_node("Cam")
	var dir := Vector3(0.45, 0.55, 0.75).normalized()
	cam.look_at_from_position(c + dir * (r / sin(deg2rad(cam.fov * 0.5)) * 0.82), c, Vector3.UP)
	vp.render_target_update_mode = Viewport.UPDATE_ONCE
	return true
