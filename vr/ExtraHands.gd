extends Reference

# More built-in VR hands (Settings > VR > Hands), made in code like the paw
# (PawHand.gd): rounded parts put together, cel shaded with a bold outline,
# lit from a fixed direction so they look the same in every background.
#   "glove"    a white cartoon glove with a puffy cuff
#   "robot"    a dark metal hand with glowing cyan joints and a palm light
#   "skeleton" a bony hand: knuckles, finger bones and wrist bones
#   "crystal"  glowing faceted crystal shards in the shape of a hand
#
# build(kind) gives the right hand, in metres with the controller at the
# origin, palm facing -Y, fingers along -Z, +X to the right (so the thumb is
# on the -X side); VRPlayer.gd and HUD.gd scale it and mirror it for the left.

const KINDS := ["glove", "robot", "skeleton", "crystal"]
# how far in front of the controller the fingertips reach (the beam starts there)
const TIPS := {"glove": 0.078, "robot": 0.085, "skeleton": 0.088, "crystal": 0.095}

const TOON := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 col_light : hint_color;
uniform vec4 col_mid : hint_color;
uniform vec4 col_dark : hint_color;
uniform float shine = 0.0;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float d = max(dot(n, l), dot(n, l2) * 0.55);
	vec3 c = mix(col_mid.rgb, col_light.rgb, smoothstep(0.12, 0.2, d));
	c = mix(col_dark.rgb, c, smoothstep(-0.38, -0.3, d));
	float s = max(dot(n, normalize(l + v)), dot(n, normalize(l2 + v)));
	c = mix(c, vec3(1.0), smoothstep(0.955, 0.97, s) * shine);
	ALBEDO = c;
}
"""

const LINE := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 line : hint_color;
uniform float width = 0.0021;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = line.rgb;
}
"""

const GLOW := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 core : hint_color;
uniform vec4 edge : hint_color;
void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = mix(edge.rgb, core.rgb, f * f) * 1.15;
}
"""

static func tip(kind: String) -> float:
	return float(TIPS.get(kind, 0.06))

static func has(kind: String) -> bool:
	return KINDS.has(kind)

# [left, right] meshes for a kind (null when it isn't one of these)
static func pair(kind: String):
	if not has(kind):
		return null
	var r = build(kind)
	if kind == "crystal":
		return [r, r] # (the same both sides)
	return [load("res://vr/VRPlayer.gd")._mirrored(r), r]

static func build(kind: String) -> ArrayMesh:
	match kind:
		"glove": return _glove()
		"robot": return _robot()
		"skeleton": return _skeleton()
		"crystal": return _crystal()
	return ArrayMesh.new()

# --- parts ---------------------------------------------------------------------

static func _sphere(r: Vector3) -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 20
	s.rings = 10
	return _scaled(s, r)

static func _capsule(radius: float, length: float) -> Mesh:
	# (along Z; `length` end to end)
	var c := CapsuleMesh.new()
	c.radius = radius
	c.mid_height = max(0.0001, length - radius * 2.0)
	c.radial_segments = 16
	c.rings = 4
	return c

static func _box(size: Vector3) -> Mesh:
	var b := CubeMesh.new()
	b.size = size
	return b

static func _cyl(radius: float, height: float, segs: int = 20) -> Mesh:
	# (along Y)
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c

# a mesh with its vertices scaled (normals fixed for the new shape)
static func _scaled(m: Mesh, s: Vector3) -> Mesh:
	var a: Array = m.surface_get_arrays(0)
	var v: PoolVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PoolVector3Array = a[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = v[i] * s
		n[i] = Vector3(n[i].x / s.x, n[i].y / s.y, n[i].z / s.z).normalized()
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	a[Mesh.ARRAY_TANGENT] = null
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out

# a part along the line from a to b (a capsule or box lying from a to b)
static func _between(a: Vector3, b: Vector3) -> Transform:
	var dir := b - a
	var z := dir.normalized()
	var up := Vector3.UP if abs(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Transform(Basis(x, y, z), (a + b) / 2.0)

static func _add(st: SurfaceTool, m: Mesh, t: Transform):
	st.append_from(m, 0, t)

static func _toon(light: Color, mid: Color, dark: Color, shine := 0.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = TOON
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_param("col_light", light)
	m.set_shader_param("col_mid", mid)
	m.set_shader_param("col_dark", dark)
	m.set_shader_param("shine", shine)
	return m

static func _line_mat(col: Color, width: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = LINE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_param("line", col)
	m.set_shader_param("width", width)
	return m

static func _glow_mat(core: Color, edge: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GLOW
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_param("core", core)
	m.set_shader_param("edge", edge)
	return m

# the body surface with its outline under it
static func _with_outline(mesh: ArrayMesh, st: SurfaceTool, body: Material, line: Material):
	var arr: Array = st.commit_to_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, line)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, body)

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# the four fingers: [x, base z, length, droop] (index to pinky), and the thumb
const FINGERS := [[-0.026, -0.026, 0.050, 0.004], [-0.009, -0.031, 0.056, 0.004], [0.009, -0.030, 0.053, 0.004], [0.026, -0.024, 0.042, 0.004]]
const THUMB_BASE := Vector3(-0.040, -0.002, 0.004)
const THUMB_TIP := Vector3(-0.062, -0.006, -0.030)

# --- glove ---------------------------------------------------------------------

static func _glove() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := _st()
	_add(st, _sphere(Vector3(0.043, 0.020, 0.040)), Transform(Basis(), Vector3(0, 0, 0.004)))
	for f in FINGERS:
		var a := Vector3(f[0], 0.002, f[1] + 0.012)
		var b := Vector3(f[0] * 1.08, -f[3], f[1] - f[2] + 0.012)
		_add(st, _capsule(0.0125, (b - a).length() + 0.025), _between(a, b))
	_add(st, _capsule(0.0135, (THUMB_TIP - THUMB_BASE).length() + 0.027), _between(THUMB_BASE, THUMB_TIP))
	# the puffy cuff, rolled over at the wrist
	var cuff := Transform(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.0, 0.054))
	_add(st, _scaled(_cyl(1.0, 1.0, 24), Vector3(0.034, 0.014, 0.020)), cuff)
	_add(st, _scaled(_cyl(1.0, 1.0, 24), Vector3(0.037, 0.005, 0.023)), Transform(cuff.basis, Vector3(0, 0.0, 0.046)))
	_with_outline(mesh, st, _toon(Color(1, 1, 1), Color(0.88, 0.88, 0.92), Color(0.70, 0.70, 0.78), 0.6), _line_mat(Color(0.08, 0.08, 0.1), 0.0022))
	# the three stitch lines on the back of the hand
	var sst := _st()
	for x in [-0.014, 0.0, 0.014]:
		_add(sst, _box(Vector3(0.0022, 0.002, 0.026)), Transform(Basis(), Vector3(x, 0.0205, 0.008)))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sst.commit_to_arrays())
	mesh.surface_set_material(mesh.get_surface_count() - 1, _toon(Color(0.1, 0.1, 0.12), Color(0.1, 0.1, 0.12), Color(0.1, 0.1, 0.12)))
	return mesh

# --- robot ---------------------------------------------------------------------

static func _robot() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var metal := _st()
	var glow := _st()
	_add(metal, _box(Vector3(0.074, 0.022, 0.060)), Transform(Basis(), Vector3(0, 0, 0.006)))
	_add(metal, _box(Vector3(0.060, 0.026, 0.020)), Transform(Basis(), Vector3(0, 0, 0.046)))
	_add(metal, _scaled(_cyl(1.0, 1.0, 16), Vector3(0.020, 0.016, 0.016)), Transform(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.064)))
	# the palm light (underneath) and the knuckle line on top
	_add(glow, _scaled(_cyl(1.0, 1.0, 20), Vector3(0.013, 0.004, 0.013)), Transform(Basis(), Vector3(0, -0.012, 0.004)))
	_add(glow, _box(Vector3(0.060, 0.003, 0.004)), Transform(Basis(), Vector3(0, 0.0115, -0.018)))
	for f in FINGERS:
		var x: float = f[0]
		var z: float = f[1] + 0.006
		var seg: float = f[2] / 3.0
		for k in 3:
			var a := Vector3(x, -k * 0.003, z - k * seg)
			_add(glow, _sphere(Vector3(0.0065, 0.0065, 0.0065)), Transform(Basis(), a))
			_add(metal, _box(Vector3(0.0125, 0.0125, seg * 0.78)), _between(a, a + Vector3(0, -0.003, -seg)).translated(Vector3(0, 0, 0)))
		_add(metal, _box(Vector3(0.013, 0.010, 0.006)), Transform(Basis(), Vector3(x, -0.009, z - f[2] - 0.001)))
	var tm := (THUMB_BASE + THUMB_TIP) / 2.0
	_add(glow, _sphere(Vector3(0.007, 0.007, 0.007)), Transform(Basis(), THUMB_BASE))
	_add(glow, _sphere(Vector3(0.0065, 0.0065, 0.0065)), Transform(Basis(), tm))
	_add(metal, _box(Vector3(0.013, 0.013, (tm - THUMB_BASE).length() * 0.8)), _between(THUMB_BASE, tm))
	_add(metal, _box(Vector3(0.012, 0.012, (THUMB_TIP - tm).length() * 0.9)), _between(tm, THUMB_TIP))
	_with_outline(mesh, metal, _toon(Color(0.62, 0.66, 0.74), Color(0.42, 0.45, 0.53), Color(0.24, 0.26, 0.32), 0.9), _line_mat(Color(0.05, 0.06, 0.09), 0.0018))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glow.commit_to_arrays())
	mesh.surface_set_material(mesh.get_surface_count() - 1, _glow_mat(Color(0.75, 1.0, 1.0), Color(0.1, 0.75, 1.0)))
	return mesh

# --- skeleton ------------------------------------------------------------------

static func _skeleton() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := _st()
	# wrist bones (carpals): a little cluster
	for p in [Vector3(-0.012, 0, 0.040), Vector3(0.0, 0.002, 0.044), Vector3(0.013, 0, 0.040), Vector3(-0.006, -0.002, 0.032), Vector3(0.007, -0.002, 0.032)]:
		_add(st, _sphere(Vector3(0.0085, 0.0075, 0.0085)), Transform(Basis(), p))
	# the two forearm bone ends
	for x in [-0.010, 0.010]:
		_add(st, _capsule(0.0075, 0.030), _between(Vector3(x, 0, 0.050), Vector3(x * 1.3, 0, 0.075)))
	for f in FINGERS:
		var base := Vector3(float(f[0]) * 0.55, 0.0, 0.030)
		var knuckle := Vector3(f[0], 0.001, f[1] + 0.004)
		_add(st, _capsule(0.0055, (knuckle - base).length()), _between(base, knuckle))
		_add(st, _sphere(Vector3(0.0072, 0.0072, 0.0072)), Transform(Basis(), knuckle))
		var seg: float = f[2] / 3.0
		var a := knuckle
		for k in 3:
			var b := a + Vector3(0, -0.0035, -seg)
			_add(st, _capsule(0.0048 - k * 0.0005, (b - a).length() + 0.004), _between(a, b))
			if k < 2:
				_add(st, _sphere(Vector3(0.0058, 0.0058, 0.0058) * (1.0 - k * 0.1)), Transform(Basis(), b))
			a = b
	var tb := Vector3(-0.016, -0.002, 0.030)
	_add(st, _capsule(0.0058, (THUMB_BASE - tb).length()), _between(tb, THUMB_BASE))
	_add(st, _sphere(Vector3(0.0072, 0.0072, 0.0072)), Transform(Basis(), THUMB_BASE))
	var tm := (THUMB_BASE + THUMB_TIP) / 2.0
	_add(st, _capsule(0.0052, (tm - THUMB_BASE).length() + 0.004), _between(THUMB_BASE, tm))
	_add(st, _sphere(Vector3(0.006, 0.006, 0.006)), Transform(Basis(), tm))
	_add(st, _capsule(0.0046, (THUMB_TIP - tm).length() + 0.004), _between(tm, THUMB_TIP))
	_with_outline(mesh, st, _toon(Color(0.98, 0.95, 0.86), Color(0.86, 0.82, 0.72), Color(0.66, 0.61, 0.52), 0.35), _line_mat(Color(0.16, 0.12, 0.10), 0.0016))
	return mesh

# --- crystal -------------------------------------------------------------------

# a long faceted shard from a to b (6 sides, pointed both ends), flat shaded
static func _shard(st: SurfaceTool, a: Vector3, b: Vector3, r: float):
	var t := _between(a, b)
	var ln := (b - a).length()
	var ring := []
	for i in 6:
		var ang: float = TAU * i / 6.0
		ring.append(t.xform(Vector3(cos(ang) * r, sin(ang) * r, -ln * 0.18)))
	var back: Vector3 = t.xform(Vector3(0, 0, ln * 0.5))
	var front: Vector3 = t.xform(Vector3(0, 0, -ln * 0.5))
	for i in 6:
		var p: Vector3 = ring[i]
		var q: Vector3 = ring[(i + 1) % 6]
		for tri in [[back, q, p], [front, p, q]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			var mid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
			if n.dot(mid - t.origin) < 0.0:
				# (facing out of the shard, wound the way Godot draws the front)
				n = -n
				tri = [tri[0], tri[2], tri[1]]
			for v in tri:
				st.add_normal(n)
				st.add_vertex(v)

static func _crystal() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := _st()
	_shard(st, Vector3(0, 0, 0.060), Vector3(0, 0, -0.024), 0.030)
	_shard(st, Vector3(-0.022, 0.002, 0.040), Vector3(-0.030, 0, -0.010), 0.014)
	_shard(st, Vector3(0.022, 0.002, 0.040), Vector3(0.030, 0, -0.010), 0.014)
	for f in FINGERS:
		_shard(st, Vector3(float(f[0]) * 0.9, 0.0, f[1] + 0.012), Vector3(float(f[0]) * 1.1, -0.004, float(f[1]) - float(f[2]) - 0.004), 0.0085)
	_shard(st, THUMB_BASE + Vector3(0.01, 0, 0.008), THUMB_TIP + Vector3(-0.003, 0, -0.004), 0.009)
	var arr: Array = st.commit_to_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, _line_mat(Color(0.18, 0.05, 0.35), 0.0016))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# (bright facets: the cel shading picks out each face, with a sparkle)
	mesh.surface_set_material(1, _toon(Color(0.95, 0.85, 1.0), Color(0.74, 0.50, 1.0), Color(0.55, 0.32, 0.92), 1.0))
	return mesh
