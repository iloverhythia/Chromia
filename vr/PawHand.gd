extends Reference

# The built-in "Furry paw" VR hand (Settings > VR > Hands): a plush cream paw
# glove with four toes, a fluffy cuff, pink toe beans and a big pink pad, each
# bean sitting on a peach seam ring like a stitched plush.
#
# Made in code (no files): lumpy ellipsoids for the fur, with a fur shader and
# a few "shells" (the same surface pushed out a little, with fewer strands each
# time) for a soft fuzzy edge, and smooth pads with a soft shine. Lit from a
# fixed direction in the world, so it looks the same in every background,
# lit or not.
#
# build() gives the right hand, in metres with the controller at the origin,
# -Z forward (VRPlayer.gd scales it and mirrors it for the left hand).

const FUR_DARK := Color(0.52, 0.46, 0.44)
const FUR_LIGHT := Color(0.95, 0.92, 0.88)
const FUR_TIP := Color(1.0, 0.985, 0.96)
const PAD_DARK := Color(0.80, 0.47, 0.47)
const PAD_LIGHT := Color(0.98, 0.72, 0.70)
const SEAM := Color(0.87, 0.64, 0.46)
const SHELLS := [0.25, 0.5, 0.75, 1.0]
const FUR_LEN := 0.0075

const FUR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
uniform vec4 fur_dark : hint_color;
uniform vec4 fur_light : hint_color;
uniform vec4 fur_tip : hint_color;
uniform float shell = 0.0;
uniform float fur_len = 0.0075;
uniform float density = 380.0;
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
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float ndl = max(dot(n, l) * 0.5 + 0.5, (dot(n, l2) * 0.5 + 0.5) * 0.7);
	ndl *= mix(0.55, 1.0, COLOR.r) + shell * 0.25 * (1.0 - COLOR.r); // creases between toes
	float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 1.7);
	vec3 cell = floor(opos * density);
	float h = hash13(cell);
	float h2 = hash13(cell + vec3(17.0, 3.0, 9.0));
	vec3 c = mix(fur_dark.rgb, fur_light.rgb, smoothstep(0.05, 0.95, ndl));
	c *= 0.88 + 0.16 * h2;
	c = mix(c, fur_tip.rgb, clamp(rim * 0.45 + shell * 0.35, 0.0, 1.0) * COLOR.r);
	if (shell > 0.0) {
		// fewer, thinner strands the further out
		vec3 f = fract(opos * density) - 0.5;
		float thick = 0.62 - shell * 0.42;
		if (h < shell * 0.85 || length(f) > thick) {
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
	float ndl = max(dot(n, l) * 0.5 + 0.5, (dot(n, l2) * 0.5 + 0.5) * 0.8);
	vec3 c = mix(pad_dark.rgb, pad_light.rgb, smoothstep(0.0, 1.0, ndl));
	float spec = pow(max(dot(reflect(-l, n), v), 0.0), 18.0) * shine;
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5) * 0.25;
	ALBEDO = c + vec3(spec) + vec3(1.0, 0.9, 0.9) * rim;
}
"""

static func build() -> ArrayMesh:
	var noise := OpenSimplexNoise.new()
	noise.seed = 7
	noise.octaves = 3
	noise.period = 0.35
	noise.persistence = 0.55
	# paw frame: palm faces -Y, toes toward -Z (forward)
	var fur := []   # [center, radii, lump size]
	fur.append([Vector3(0, 0, 0.004), Vector3(0.050, 0.034, 0.050), 0.0035])  # palm
	fur.append([Vector3(0, 0.004, 0.066), Vector3(0.057, 0.045, 0.040), 0.009]) # cuff
	var toes := [
		[Vector3(-0.046, 0.004, -0.032), Vector3(0.018, 0.022, 0.020)],
		[Vector3(-0.017, 0.006, -0.050), Vector3(0.020, 0.024, 0.022)],
		[Vector3(0.017, 0.006, -0.050), Vector3(0.020, 0.024, 0.022)],
		[Vector3(0.046, 0.004, -0.032), Vector3(0.018, 0.022, 0.020)],
	]
	for t in toes:
		fur.append([t[0], t[1], 0.003])
	# pads: puffy pillows on the palm side, each on a flatter peach seam ring
	# [centre on the palm plane, x radius, z radius, puff, shape (0 oval, 1 the
	# big pad's rounded triangle), tilt toward the toes]
	var pads := [[Vector3(0, -0.0355, 0.008), 0.024, 0.021, 0.0095, 1, 0.0]]
	for t in toes:
		var c: Vector3 = t[0]
		pads.append([Vector3(c.x * 1.03, -0.0205, c.z - 0.003), 0.0115, 0.0125, 0.0075, 0, -0.35])
	# paw frame -> controller: palm turned in (toward -X for the right hand)
	# and down, the paw around the controller's handle
	var place := Transform(Basis(Vector3(0, 0, 1), deg2rad(-55.0)), Vector3(0.0, -0.005, 0.028))

	var fur_st := SurfaceTool.new()
	fur_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in fur:
		_ellipsoid(fur_st, place, e[0], e[1], 20, 12, noise, e[2], fur)
	fur_st.index() # shared corners: about a sixth of the vertices
	var fur_arrays: Array = fur_st.commit_to_arrays()

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
		m.render_priority = int(s * 5)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)

	var pad_shader := Shader.new()
	pad_shader.code = PAD_SHADER
	for part in [[false, PAD_DARK, PAD_LIGHT, 0.35], [true, SEAM.darkened(0.15), SEAM, 0.12]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in pads:
			if part[0]: # the seam: a bit bigger, flatter, just behind the pad
				_pillow(st, place, e[0] + Vector3(0, 0.0012, 0), e[1] * 1.2, e[2] * 1.2, e[3] * 0.42, e[4], e[5])
			else:
				_pillow(st, place, e[0], e[1], e[2], e[3], e[4], e[5])
		st.index()
		st.generate_normals()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		var pm := ShaderMaterial.new()
		pm.shader = pad_shader
		pm.set_shader_param("pad_dark", part[1])
		pm.set_shader_param("pad_light", part[2])
		pm.set_shader_param("shine", part[3])
		mesh.surface_set_material(mesh.get_surface_count() - 1, pm)
	return mesh

# An ellipsoid, optionally lumpy (fluffy clumps), with smooth normals.
static func _ellipsoid(st: SurfaceTool, place: Transform, c: Vector3, r: Vector3, seg: int, rings: int, noise, lump: float, others: Array = []):
	var pts := []
	var nrm := []
	var aos := []
	for j in range(rings + 1):
		var v := float(j) / rings
		var phi := v * PI
		var row := []
		var nrow := []
		var arow := []
		for i in range(seg + 1):
			var u := float(i % seg) / seg
			var th := u * TAU
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var k := 1.0
			if noise != null and lump > 0.0:
				var q: Vector3 = d * 2.0 + c * 40.0
				k += noise.get_noise_3dv(q * 3.0) * lump / max(r.x, 0.001) * 2.2
			var p := Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * k
			row.append(place.xform(c + p))
			# darker where it tucks into another part (between the toes, the cuff)
			var ao := 1.0
			for o in others:
				if o[0] == c:
					continue
				var rel: Vector3 = (c + p - o[0])
				var dn: float = Vector3(rel.x / o[1].x, rel.y / o[1].y, rel.z / o[1].z).length()
				ao = min(ao, clamp((dn - 0.92) / 0.28, 0.0, 1.0))
			arow.append(ao)
			# ellipsoid normal (the lumps' slopes come from the shading noise)
			nrow.append(place.basis.xform(Vector3(d.x / r.x, d.y / r.y, d.z / r.z)).normalized())
		pts.append(row)
		nrm.append(nrow)
		aos.append(arow)
	for j in range(rings):
		for i in range(seg):
			var quad := [[j, i], [j + 1, i + 1], [j, i + 1], [j, i], [j + 1, i], [j + 1, i + 1]]
			for q in quad:
				st.add_color(Color(aos[q[0]][q[1]], 1, 1))
				st.add_normal(nrm[q[0]][q[1]])
				st.add_vertex(pts[q[0]][q[1]])

# A puffy pad on the palm side (-Y): an outline in the palm plane, domed out
# along -Y. shape 0: an oval; 1: a rounded triangle pointing at the toes with
# two lobes at the back (the big pad).
static func _pillow(st: SurfaceTool, place: Transform, c: Vector3, rx: float, rz: float, puff: float, shape: int, tilt: float):
	var seg := 28
	var rings := 6
	var tb := Basis(Vector3(1, 0, 0), tilt) # leans the toe beans forward
	var ring_pts := []
	for k in range(rings + 1):
		var rho := float(k) / rings
		var row := []
		for i in range(seg):
			var th := float(i) / seg * TAU
			var rr := 1.0
			if shape == 1:
				# lobes toward the toes (-Z) and the two back corners
				rr = 1.0 + 0.13 * cos(3.0 * (th + PI / 2.0)) - 0.04 * cos(6.0 * (th + PI / 2.0))
			var x := cos(th) * rx * rr * rho
			var z := sin(th) * rz * rr * rho
			var h := puff * pow(max(0.0, 1.0 - rho * rho), 0.55)
			row.append(place.xform(c + tb.xform(Vector3(x, -h, z))))
		ring_pts.append(row)
	for k in range(rings):
		for i in range(seg):
			var i2 := (i + 1) % seg
			var a: Vector3 = ring_pts[k][i]
			var b: Vector3 = ring_pts[k][i2]
			var cc: Vector3 = ring_pts[k + 1][i2]
			var d: Vector3 = ring_pts[k + 1][i]
			for v in [a, b, cc, a, cc, d]:
				st.add_vertex(v)
