extends Reference

# The built-in "Furry paws" VR hand (Settings > VR > Hands): a cartoon paw
# mitten: one rounded shape with four round toe bumps blended into the palm
# and a cuff, cel shaded in a few clean tones with a bold outline, and glossy
# pink toe beans and main pad on the palm, each with a darker rim.
#
# Made in code (no files). The shape is a smooth blend of rounded parts (a
# signed distance field) turned into one mesh, so the toes melt into the paw
# with soft creases. Lit from a fixed direction in the world (with a soft
# fill), so it looks the same in every background. 4 draws per hand.
#
# build() gives the right hand, in metres with the controller at the origin,
# -Z forward (VRPlayer.gd scales it and mirrors it for the left hand).

const BODY_LIGHT := Color(1.0, 0.975, 0.945)
const BODY_MID := Color(0.90, 0.84, 0.84)
const BODY_DARK := Color(0.74, 0.66, 0.72)
const LINE := Color(0.27, 0.17, 0.22)
const LINE_WIDTH := 0.0021
const PAD_DARK := Color(0.93, 0.52, 0.60)
const PAD_LIGHT := Color(1.0, 0.70, 0.75)
const PAD_RIM := Color(0.62, 0.26, 0.36)

# paw frame: palm faces -Y, toes toward -Z (forward), +X to the right
# [centre, radii]
const PARTS := [
	[Vector3(0, 0.0, 0.008), Vector3(0.048, 0.028, 0.040)],          # palm
	[Vector3(0, 0.001, 0.050), Vector3(0.043, 0.032, 0.020)],        # cuff
	[Vector3(-0.043, 0.008, -0.020), Vector3(0.019, 0.021, 0.019)],  # toes
	[Vector3(-0.015, 0.010, -0.032), Vector3(0.020, 0.022, 0.020)],
	[Vector3(0.015, 0.010, -0.032), Vector3(0.020, 0.022, 0.020)],
	[Vector3(0.043, 0.008, -0.020), Vector3(0.019, 0.021, 0.019)],
]
const BLEND := 0.0035 # how softly the parts melt together (small: clear creases)
# how far in front of the controller the toes reach (the beam starts there)
const TIP := 0.052
const CENTRE := Vector3(0, 0.0, 0.006)

const TOON_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 col_light : hint_color;
uniform vec4 col_mid : hint_color;
uniform vec4 col_dark : hint_color;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float d = max(dot(n, l), dot(n, l2) * 0.55);
	d -= (1.0 - COLOR.r) * 0.75; // the creases between the toes and at the cuff
	vec3 c = mix(col_mid.rgb, col_light.rgb, smoothstep(0.12, 0.2, d));
	c = mix(col_dark.rgb, c, smoothstep(-0.38, -0.3, d));
	ALBEDO = c;
}
"""

const LINE_SHADER := """
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

const PAD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 pad_dark : hint_color;
uniform vec4 pad_light : hint_color;
uniform float shine = 1.0;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float d = max(dot(n, l), dot(n, l2) * 0.8);
	vec3 c = mix(pad_dark.rgb, pad_light.rgb, smoothstep(0.05, 0.13, d));
	// a cartoon shine spot
	float s1 = max(dot(n, normalize(l + v)), dot(n, normalize(l2 + v)));
	c = mix(c, vec3(1.0, 0.96, 0.97), smoothstep(0.955, 0.965, s1) * shine);
	ALBEDO = c;
}
"""

# --- The shape ---------------------------------------------------------------
static func _smin(a: float, b: float, k: float) -> float:
	var h: float = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerp(b, a, h) - k * h * (1.0 - h)

static func _ell(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q: Vector3 = p - c
	var k0: float = Vector3(q.x / r.x, q.y / r.y, q.z / r.z).length()
	var k1: float = Vector3(q.x / (r.x * r.x), q.y / (r.y * r.y), q.z / (r.z * r.z)).length()
	if k1 < 0.000001:
		return -min(r.x, min(r.y, r.z))
	return k0 * (k0 - 1.0) / k1

static func sdf(p: Vector3) -> float:
	var d := 1.0
	for part in PARTS:
		d = _smin(d, _ell(p, part[0], part[1]), BLEND)
	return d

static func _grad(p: Vector3) -> Vector3:
	var e := 0.0005
	return Vector3(
		sdf(p + Vector3(e, 0, 0)) - sdf(p - Vector3(e, 0, 0)),
		sdf(p + Vector3(0, e, 0)) - sdf(p - Vector3(0, e, 0)),
		sdf(p + Vector3(0, 0, e)) - sdf(p - Vector3(0, 0, e))).normalized()

# where the surface is along a direction from the centre
static func _surface(d: Vector3) -> Vector3:
	var lo := 0.0
	var hi := 0.13
	for _i in range(28):
		var mid: float = (lo + hi) * 0.5
		if sdf(CENTRE + d * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return CENTRE + d * ((lo + hi) * 0.5)

# where the palm side's surface is under a point (coming up from below)
static func _palm_point(x: float, z: float) -> Vector3:
	var lo := -0.08
	var hi := 0.0
	for _i in range(28):
		var mid: float = (lo + hi) * 0.5
		if sdf(Vector3(x, mid, z)) < 0.0:
			hi = mid
		else:
			lo = mid
	return Vector3(x, (lo + hi) * 0.5, z)

static func build() -> ArrayMesh:
	# paw frame -> controller: the back of the paw up (so you see the toes
	# when you look at your hand), a little turned in, toes curled down a bit
	var place := Transform(Basis(Vector3(0, 0, 1), deg2rad(-18.0)) * Basis(Vector3(1, 0, 0), deg2rad(10.0)), Vector3(0.0, -0.006, 0.026))

	# fur: one closed surface around the centre
	var seg := 72
	var rings := 44
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(rings + 1):
		var phi: float = float(j) / rings * PI
		for i in range(seg):
			var th: float = float(i) / seg * TAU
			# poles along the paw's length (z), for even detail on the toes
			var d := Vector3(sin(phi) * cos(th), sin(phi) * sin(th), cos(phi))
			var p := _surface(d)
			var nn := _grad(p)
			# darker in the creases (between the toes, at the cuff)
			var ao: float = clamp(sdf(p + nn * 0.011) / 0.011, 0.0, 1.0)
			st.add_color(Color(ao, 1, 1))
			st.add_normal(place.basis.xform(nn).normalized())
			st.add_vertex(place.xform(p))
	for j in range(rings):
		for i in range(seg):
			var i2: int = (i + 1) % seg
			var a: int = j * seg + i
			var b: int = j * seg + i2
			var c: int = (j + 1) * seg + i2
			var dd: int = (j + 1) * seg + i
			for k in [a, b, c, a, c, dd]:
				st.add_index(k)
	var body_arrays: Array = st.commit_to_arrays()

	var mesh := ArrayMesh.new()
	# the bold outline: the same surface pushed out, drawn from behind
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays)
	var lsh := Shader.new()
	lsh.code = LINE_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = lsh
	lm.set_shader_param("line", LINE)
	lm.set_shader_param("width", LINE_WIDTH)
	mesh.surface_set_material(0, lm)
	# the body, cel shaded
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays)
	var tsh := Shader.new()
	tsh.code = TOON_SHADER
	var tm := ShaderMaterial.new()
	tm.shader = tsh
	tm.set_shader_param("col_light", BODY_LIGHT)
	tm.set_shader_param("col_mid", BODY_MID)
	tm.set_shader_param("col_dark", BODY_DARK)
	mesh.surface_set_material(1, tm)

	# pads: [x, z, x radius, z radius, puff, shape (0 oval, 1 main pad)]
	var pads := [[0.0, 0.013, 0.027, 0.022, 0.0075, 1]]
	for t in PARTS.slice(2, 5):
		var tc: Vector3 = t[0]
		pads.append([tc.x, tc.z - 0.002, 0.0125, 0.0135, 0.0055, 0])
	var pad_shader := Shader.new()
	pad_shader.code = PAD_SHADER
	for part in [[false, PAD_DARK, PAD_LIGHT, 1.0], [true, PAD_RIM, PAD_RIM, 0.0]]:
		var ps := SurfaceTool.new()
		ps.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in pads:
			var base := _palm_point(e[0], e[1])
			var nrm := _grad(base)
			if part[0]:
				_pillow(ps, place, base + nrm * 0.0024, nrm, e[2] * 1.14, e[3] * 1.14, e[4] * 0.3, e[5])
			else:
				_pillow(ps, place, base + nrm * 0.0032, nrm, e[2], e[3], e[4], e[5])
		ps.index()
		ps.generate_normals()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ps.commit_to_arrays())
		var pm := ShaderMaterial.new()
		pm.shader = pad_shader
		pm.set_shader_param("pad_dark", part[1])
		pm.set_shader_param("pad_light", part[2])
		pm.set_shader_param("shine", part[3])
		mesh.surface_set_material(mesh.get_surface_count() - 1, pm)
	return mesh

# A puffy pad sitting on the surface at c (facing out along nrm): an outline,
# domed outward. shape 0: an oval; 1: the main pad, a soft rounded triangle
# pointing at the toes with two lobes at the back.
static func _pillow(st: SurfaceTool, place: Transform, c: Vector3, nrm: Vector3, rx: float, rz: float, puff: float, shape: int):
	var seg := 32
	var rings := 12
	# a frame on the surface: out along nrm, x across the paw, z along it
	var out: Vector3 = nrm.normalized()
	var ax: Vector3 = (Vector3(1, 0, 0) - out * out.x).normalized()
	var az: Vector3 = ax.cross(out).normalized()
	if az.z < 0.0:
		az = -az
	var rows := []
	for k in range(rings + 1):
		var rho: float = float(k) / rings
		var row := []
		for i in range(seg):
			var th: float = float(i) / seg * TAU
			var rr := 1.0
			if shape == 1:
				rr = 1.0 + 0.12 * cos(3.0 * (th + PI / 2.0)) - 0.035 * cos(6.0 * (th + PI / 2.0))
			var x: float = cos(th) * rx * rr * rho
			var z: float = sin(th) * rz * rr * rho
			var h: float = puff * sqrt(max(0.0, 1.0 - rho * rho))
			row.append(place.xform(c + ax * x + az * z + out * h))
		rows.append(row)
	for k in range(rings):
		for i in range(seg):
			var i2: int = (i + 1) % seg
			var a: Vector3 = rows[k][i]
			var b: Vector3 = rows[k][i2]
			var cc: Vector3 = rows[k + 1][i2]
			var d: Vector3 = rows[k + 1][i]
			for v in [a, b, cc, a, cc, d]:
				st.add_vertex(v)
