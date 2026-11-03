extends Reference
# Your avatar's look (Settings > Player Avatar > Go to editor): its colours and
# the items it wears. Saved as Rhythia.avatar; shown on the avatar in replays
# with the alternate camera and in the 3rd-person spectate view, and sent to
# the people watching you.
#
# Items are either parts of the avatar scene (prefabs/Avatar.tscn: its
# Head/Accessories and Torso/Shirts) or made here from simple shapes. Head
# items are in the head's space (a cube from -1 to 1, face toward -Z); torso
# items in the torso's (the same cube, stretched by the torso).

# id, name shown, where ("head" / "torso"), scene node name ("" = made here)
const ITEMS := [
	["headset", "Headset", "head", "Headset"],
	["cubella_hair", "Cubella hair", "head", "CubellaHair"],
	["top_hat", "Top hat", "head", ""],
	["cap", "Cap", "head", ""],
	["crown", "Crown", "head", ""],
	["cat_ears", "Cat ears", "head", ""],
	["horns", "Horns", "head", ""],
	["halo", "Halo", "head", ""],
	["glasses", "Glasses", "head", ""],
	["bow", "Bow", "head", ""],
	["scarf", "Scarf", "torso", ""],
	["tie", "Tie", "torso", ""],
	["bowtie", "Bow tie", "torso", ""],
	["cape", "Cape", "torso", ""],
	["bikini", "Bikini", "torso", "CubellaBikini"],
]
const DEFAULT := {"head": "#ffffff", "body": "#ffffff", "eyes": "#000000", "items": []}
const BUILT := "AvatarLookItem" # (group of the parts made here)

static func normalized(d) -> Dictionary:
	var out: Dictionary = DEFAULT.duplicate(true)
	if d is Dictionary:
		for k in ["head", "body", "eyes"]:
			if String(d.get(k, "")).is_valid_html_color():
				out[k] = String(d[k])
		var items := []
		var known := []
		for it in ITEMS:
			known.append(it[0])
		for id in (d.get("items", []) if d.get("items") is Array else []):
			if String(id) in known and not (String(id) in items) and items.size() < 12:
				items.append(String(id))
		out["items"] = items
	return out

static func item(id: String):
	for it in ITEMS:
		if it[0] == id:
			return it
	return null

# avatar: an instance of prefabs/Avatar.tscn
static func apply(avatar: Node, data):
	if avatar == null:
		return
	var d := normalized(data)
	var head = avatar.get_node_or_null("Head")
	var torso = avatar.get_node_or_null("Torso")
	# colours (own copies of the materials: the scene's are shared)
	if head is MeshInstance:
		var m = head.material_override
		if m is SpatialMaterial:
			if not head.has_meta("own_mat"):
				m = m.duplicate()
				head.material_override = m
				head.set_meta("own_mat", true)
			m.albedo_color = Color(d.head)
		for eye in ["EyeL", "EyeR"]:
			_paint(head.get_node_or_null(eye), Color(d.eyes))
	_paint(torso, Color(d.body))
	_paint(avatar.get_node_or_null("ArmL/Pointer"), Color(d.body))
	_paint(avatar.get_node_or_null("ArmR/Mesh"), Color(d.body))
	# items: the scene's own, shown or hidden
	for it in ITEMS:
		if it[3] == "":
			continue
		var parent = head.get_node_or_null("Accessories") if it[2] == "head" else (torso.get_node_or_null("Shirts") if torso else null)
		var n = parent.get_node_or_null(it[3]) if parent else null
		if n is Spatial:
			n.visible = it[0] in d.items
	# and the ones made here, made again
	for n in _built_under(avatar):
		n.get_parent().remove_child(n)
		n.queue_free()
	for id in d.items:
		var it = item(id)
		if it == null or it[3] != "":
			continue
		var parent = head if it[2] == "head" else torso
		if parent is Spatial:
			var made := build(id)
			if made != null:
				made.add_to_group(BUILT)
				parent.add_child(made)

static func _built_under(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c.is_in_group(BUILT):
			out.append(c)
		out += _built_under(c)
	return out

static func _paint(mi, col: Color):
	if not (mi is MeshInstance) or mi.mesh == null:
		return
	var m = mi.get_surface_material(0)
	if m == null:
		m = mi.mesh.surface_get_material(0)
	if m == null:
		return
	if not mi.has_meta("own_mat"):
		m = m.duplicate()
		mi.set_surface_material(0, m)
		mi.set_meta("own_mat", true)
	if m is ShaderMaterial:
		m.set_shader_param("notecolor", col)
	elif m is SpatialMaterial:
		m.albedo_color = col

# --- the items made from shapes ------------------------------------------------------
static func _mat(col: Color, glow := false) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = col
	if glow:
		m.emission_enabled = true
		m.emission = col
	return m

static func _part(mesh: Mesh, col: Color, pos: Vector3, rot_deg := Vector3.ZERO, glow := false) -> MeshInstance:
	var mi := MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = _mat(col, glow)
	mi.transform = Transform(Basis(Vector3(deg2rad(rot_deg.x), deg2rad(rot_deg.y), deg2rad(rot_deg.z))), pos)
	return mi

static func _cyl(top: float, bottom: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func _box(x: float, y: float, z: float) -> CubeMesh:
	var c := CubeMesh.new()
	c.size = Vector3(x, y, z)
	return c

static func _prism(x: float, y: float, z: float) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = Vector3(x, y, z)
	return p

static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s

static func build(id: String) -> Spatial:
	var root := Spatial.new()
	root.name = "Look_" + id
	var black := Color(0.08, 0.07, 0.09)
	match id:
		"top_hat":
			root.add_child(_part(_cyl(1.25, 1.25, 0.12), black, Vector3(0, 1.08, 0)))
			root.add_child(_part(_cyl(0.78, 0.8, 1.1), black, Vector3(0, 1.66, 0)))
			root.add_child(_part(_cyl(0.81, 0.82, 0.22), Color(0.75, 0.12, 0.2), Vector3(0, 1.26, 0)))
		"cap":
			var dome := SphereMesh.new()
			dome.radius = 1.08
			dome.height = 1.08
			dome.is_hemisphere = true
			root.add_child(_part(dome, Color(0.2, 0.42, 0.9), Vector3(0, 0.55, 0)))
			root.add_child(_part(_box(1.5, 0.08, 1.0), Color(0.16, 0.34, 0.78), Vector3(0, 0.6, -1.25)))
		"crown":
			var gold := Color(1.0, 0.8, 0.2)
			root.add_child(_part(_cyl(0.95, 0.88, 0.45), gold, Vector3(0, 1.22, 0), Vector3.ZERO, true))
			for k in range(6):
				var a := TAU * k / 6.0
				root.add_child(_part(_prism(0.45, 0.5, 0.12), gold, Vector3(sin(a) * 0.9, 1.68, cos(a) * 0.9), Vector3(0, rad2deg(a), 0), true))
			root.add_child(_part(_ball(0.14), Color(0.9, 0.15, 0.3), Vector3(0, 1.25, -0.95), Vector3.ZERO, true))
		"cat_ears":
			for sx in [-1.0, 1.0]:
				root.add_child(_part(_prism(0.7, 0.8, 0.25), Color(0.25, 0.2, 0.25), Vector3(0.6 * sx, 1.35, 0), Vector3(0, 0, -12 * sx)))
				root.add_child(_part(_prism(0.4, 0.5, 0.05), Color(1.0, 0.6, 0.72), Vector3(0.6 * sx, 1.3, -0.14), Vector3(0, 0, -12 * sx)))
		"horns":
			for sx in [-1.0, 1.0]:
				root.add_child(_part(_cyl(0.0, 0.22, 0.85), Color(0.85, 0.82, 0.74), Vector3(0.62 * sx, 1.3, 0), Vector3(0, 0, -22 * sx)))
		"halo":
			for k in range(20):
				var a := TAU * k / 20.0
				root.add_child(_part(_ball(0.13), Color(1.0, 0.92, 0.45), Vector3(sin(a) * 0.85, 1.75, cos(a) * 0.85), Vector3.ZERO, true))
		"glasses":
			for sx in [-1.0, 1.0]:
				root.add_child(_part(_box(0.62, 0.42, 0.08), black, Vector3(0.36 * sx, 0.32, -1.06)))
				root.add_child(_part(_box(0.48, 0.28, 0.1), Color(0.35, 0.75, 1.0, 1.0), Vector3(0.36 * sx, 0.32, -1.08)))
			root.add_child(_part(_box(0.2, 0.07, 0.08), black, Vector3(0, 0.38, -1.06)))
		"bow":
			var pink := Color(1.0, 0.4, 0.65)
			root.add_child(_part(_prism(0.55, 0.5, 0.2), pink, Vector3(0.62, 1.12, -0.2), Vector3(0, 0, 90)))
			root.add_child(_part(_prism(0.55, 0.5, 0.2), pink, Vector3(1.08, 1.12, -0.2), Vector3(0, 0, -90)))
			root.add_child(_part(_ball(0.16), pink.darkened(0.15), Vector3(0.85, 1.12, -0.2)))
		"scarf":
			root.add_child(_part(_box(2.3, 0.35, 2.3), Color(0.85, 0.15, 0.2), Vector3(0, 0.9, 0)))
			root.add_child(_part(_box(0.45, 1.1, 0.12), Color(0.85, 0.15, 0.2), Vector3(0.5, 0.25, -1.18)))
		"tie":
			root.add_child(_part(_box(0.4, 0.25, 0.1), Color(0.15, 0.3, 0.75), Vector3(0, 0.75, -1.06)))
			root.add_child(_part(_box(0.32, 1.2, 0.08), Color(0.15, 0.3, 0.75), Vector3(0, 0.0, -1.06)))
		"bowtie":
			var red := Color(0.8, 0.1, 0.18)
			root.add_child(_part(_prism(0.5, 0.45, 0.12), red, Vector3(-0.26, 0.82, -1.07), Vector3(0, 0, 90)))
			root.add_child(_part(_prism(0.5, 0.45, 0.12), red, Vector3(0.26, 0.82, -1.07), Vector3(0, 0, -90)))
			root.add_child(_part(_box(0.16, 0.2, 0.14), red.darkened(0.2), Vector3(0, 0.82, -1.08)))
		"cape":
			root.add_child(_part(_box(2.0, 2.0, 0.08), Color(0.45, 0.12, 0.6), Vector3(0, -0.15, 1.12), Vector3(-6, 0, 0)))
			root.add_child(_part(_box(2.1, 0.2, 2.1), Color(0.55, 0.16, 0.72), Vector3(0, 0.92, 0)))
		_:
			return null
	return root
