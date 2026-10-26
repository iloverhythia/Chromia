extends Reference

# The built-in "Furry paws" VR hand (Settings > VR > Hands): a soft plush paw
# mitten, like the fluffy paw gloves: one rounded shape with four toe bumps
# blended into the palm, a fluffy cuff, short soft fur, and big pink toe beans
# and a main pad on the palm, each on a peach seam ring.
#
# Made in code (no files). The shape is a smooth blend of rounded parts (a
# signed distance field) turned into one mesh, so the toes melt into the paw
# with soft creases instead of looking like separate balls. Fur: a fur shader
# plus a few "shells" (the surface pushed out a little, fewer strands each
# time) for a fuzzy edge. Lit from a fixed direction in the world (with a soft
# fill), so it looks the same in every background.
#
# build() gives the right hand, in metres with the controller at the origin,
# -Z forward (VRPlayer.gd scales it and mirrors it for the left hand).

const FUR_DARK := Color(0.60, 0.53, 0.50)
const FUR_LIGHT := Color(0.97, 0.94, 0.90)
const FUR_TIP := Color(1.0, 0.99, 0.97)
const PAD_DARK := Color(0.86, 0.50, 0.53)
const PAD_LIGHT := Color(1.0, 0.76, 0.76)
const SEAM := Color(0.90, 0.68, 0.50)
const SHELLS := [0.33, 0.66, 1.0]
const FUR_LEN := 0.0045

# paw frame: palm faces -Y, toes toward -Z (forward), +X to the right
# [centre, radii]
const PARTS := [
	[Vector3(0, 0.0, 0.008), Vector3(0.048, 0.027, 0.040)],          # palm
	[Vector3(0, 0.001, 0.050), Vector3(0.044, 0.032, 0.021)],        # cuff
	[Vector3(-0.042, 0.008, -0.020), Vector3(0.0185, 0.021, 0.0195)], # toes
	[Vector3(-0.0148, 0.010, -0.031), Vector3(0.0195, 0.022, 0.0205)],
	[Vector3(0.0148, 0.010, -0.031), Vector3(0.0195, 0.022, 0.0205)],
	[Vector3(0.042, 0.008, -0.020), Vector3(0.0185, 0.021, 0.0195)],
]
const BLEND := 0.0045 # how softly the parts melt together (small: clear creases)
# how far in front of the controller the toes reach (the beam starts there)
const TIP := 0.052
const CENTRE := Vector3(0, 0.0, 0.006)

const FUR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
uniform vec4 fur_dark : hint_color;
uniform vec4 fur_light : hint_color;
uniform vec4 fur_tip : hint_color;
uniform float shell = 0.0;
uniform float fur_len = 0.0045;
uniform float density = 520.0;
varying vec3 opos;
void vertex() {
	opos = VERTEX;
	VERTEX += NORMAL * shell * fur_len;
}
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float ndl = max(dot(n, l) * 0.5 + 0.5, (dot(n, l2) * 0.5 + 0.5) * 0.75);
	float ao = COLOR.r;
	ndl *= mix(0.42, 1.0, ao);
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.0);
	vec3 cell = floor(opos * density);
	float h = hash13(cell);
	float h2 = hash13(cell + vec3(17.0, 3.0, 9.0));
	vec3 c = mix(fur_dark.rgb, fur_light.rgb, smoothstep(0.1, 0.95, ndl));
	c *= 0.94 + 0.08 * h2;
	c = mix(c, fur_tip.rgb, clamp(rim * 0.5 + shell * 0.25, 0.0, 1.0) * ao);
	if (shell > 0.0) {
		// soft fuzz: fewer, thinner strands the further out
		vec3 f = fract(opos * density) - 0.5;
		if (h < shell * 0.6 || length(f) > 0.75 - shell * 0.4) {
			discard;
		}
	}
	ALBEDO = c;
}
"""

const PAD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 pad_dark : hint_color;
uniform vec4 pad_light : hint_color;
uniform float shine = 0.35;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float ndl = max(dot(n, l) * 0.5 + 0.5, (dot(n, l2) * 0.5 + 0.5) * 0.85);
	vec3 c = mix(pad_dark.rgb, pad_light.rgb, smoothstep(0.0, 1.0, ndl));
	float spec = (pow(max(dot(n, normalize(l2 + v)), 0.0), 30.0) + pow(max(dot(n, normalize(l + v)), 0.0), 30.0)) * shine;
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5) * 0.2;
	ALBEDO = c + vec3(spec) + vec3(1.0, 0.92, 0.92) * rim;
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
	var seg := 40
	var rings := 26
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
			var ao: float = clamp(sdf(p + nn * 0.008) / 0.008, 0.0, 1.0)
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
	var fur_arrays: Array = st.commit_to_arrays()

	var mesh := ArrayMesh.new()
	var fur_shader := Shader.new()
	fur_shader.code = FUR_SHADER
	for s in [0.0] + SHELLS:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fur_arrays)
		var m := ShaderMaterial.new()
		m.shader = fur_shader
		m.set_shader_param("fur_dark", FUR_DARK)
		m.set_shader_param("fur_light", FUR_LIGHT)
		m.set_shader_param("fur_tip", FUR_TIP)
		m.set_shader_param("shell", s)
		m.set_shader_param("fur_len", FUR_LEN)
		m.render_priority = int(s * 3)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)

	# pads: [x, z, x radius, z radius, puff, shape (0 oval, 1 main pad)]
	var pads := [[0.0, 0.012, 0.026, 0.021, 0.008, 1]]
	for t in PARTS.slice(2, 5):
		var tc: Vector3 = t[0]
		pads.append([tc.x, tc.z - 0.002, 0.0115, 0.0125, 0.006, 0])
	var pad_shader := Shader.new()
	pad_shader.code = PAD_SHADER
	for part in [[false, PAD_DARK, PAD_LIGHT, 0.3], [true, SEAM.darkened(0.15), SEAM, 0.1]]:
		var ps := SurfaceTool.new()
		ps.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in pads:
			var base := _palm_point(e[0], e[1])
			var nrm := _grad(base)
			if part[0]:
				_pillow(ps, place, base + nrm * 0.0028, nrm, e[2] * 1.22, e[3] * 1.22, e[4] * 0.35, e[5])
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
