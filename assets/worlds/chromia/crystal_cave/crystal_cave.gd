extends "res://assets/worlds/chromia/chromia_world.gd"

# Crystal Cave: a dark cavern full of floating crystals that turn slowly, their
# facets shimmering through every colour like opal, with sparkles drifting
# between them and a faint glow from deep in the cave. A hit lights every
# crystal's edges in the note's colour.

const CRYSTALS := 70
const SPARKLES := 180

func sky_color() -> Color:
	return Color("#030a10")

func uses_fog() -> bool:
	return false

# one crystal: six sides, a long point up and a short one down (flat facets)
static func crystal_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := []
	for k in 6:
		var a = TAU * float(k) / 6.0
		ring.append(Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32))
	var top := Vector3(0, 1.25, 0)
	var mid_up := 0.55
	var bottom := Vector3(0, -0.55, 0)
	for k in 6:
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 6]
		var a2 := a + Vector3(0, mid_up, 0)
		var b2 := b + Vector3(0, mid_up, 0)
		for tri in [[a, b, b2], [a, b2, a2], [a2, b2, top], [b, a, bottom]]:
			var nrm: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			# (outwards: flip if it points in)
			var centre: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
			if nrm.dot(centre - Vector3(0, 0.3, 0)) < 0:
				nrm = -nrm
			for v in tri:
				st.add_normal(nrm)
				st.add_uv(Vector2(float(k), 0.0))
				st.add_vertex(v)
	return st.commit()

func _build():
	# the cave beyond: dark, with soft glows of colour deep inside
	sky_dome("""
void fragment() {
	vec3 d = normalize(v_dir);
	vec3 col = mix(vec3(0.004, 0.02, 0.03), vec3(0.015, 0.008, 0.035), smoothstep(-0.3, 0.6, d.y));
	col += vec3(0.02, 0.3, 0.32) * pow(max(dot(d, normalize(vec3(-0.6, -0.1, -1.0))), 0.0), 30.0) * 0.25;
	col += vec3(0.3, 0.05, 0.35) * pow(max(dot(d, normalize(vec3(0.7, 0.25, -1.0))), 0.0), 24.0) * 0.2;
	col += vec3(0.08, 0.1, 0.4) * pow(max(dot(d, normalize(vec3(0.0, -0.5, -1.0))), 0.0), 16.0) * 0.15;

	ALBEDO = col * (1.0 + flash() * 0.3) + dither(FRAGCOORD.xy);
}
""")

	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = crystal_mesh()
	mm.instance_count = CRYSTALS
	var n := 0
	while n < CRYSTALS:
		var p := Vector3(rng.randf_range(-45, 45), rng.randf_range(-22, 26), rng.randf_range(-48, -10))
		# (none round the grid and its panels: they'd clutter what you read and aim at.
		# The space kept clear widens with distance, like the view does.)
		var clear := 0.8 * (-p.z + 3.5)
		if abs(p.x) < clear and abs(p.y) < clear * 0.7:
			continue
		var s := rng.randf_range(0.7, 2.6) * (1.0 + (-p.z - 6.0) / 40.0)
		var basis := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, TAU))
		mm.set_instance_transform(n, Transform(basis.scaled(Vector3(s, s, s)), p))
		n += 1
	var mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 v_n;
varying float v_seed;
varying vec3 v_world;
vec3 spin(vec3 v, float a) { return vec3(v.x * cos(a) - v.z * sin(a), v.y, v.x * sin(a) + v.z * cos(a)); }
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash(o.x * 1.7 + o.y * 4.3 + o.z * 2.9);
	float a = TIME * (0.15 + v_seed * 0.35) * (v_seed < 0.5 ? 1.0 : -1.0);
	VERTEX = spin(VERTEX, a);
	NORMAL = spin(NORMAL, a);
	VERTEX.y += sin(TIME * 0.5 + v_seed * 20.0) * 0.12;
	v_n = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
vec3 opal(float t) {
	// a rainbow that stays soft (no muddy colours)
	// (gem colours: aqua, violet, rose, round and round)
	vec3 aqua = vec3(0.15, 0.95, 0.85);
	vec3 violet = vec3(0.5, 0.28, 1.0);
	vec3 rose = vec3(1.0, 0.35, 0.7);
	float x = fract(t) * 3.0;
	vec3 c = x < 1.0 ? mix(aqua, violet, smoothstep(0.0, 1.0, x)) : (x < 2.0 ? mix(violet, rose, smoothstep(1.0, 2.0, x)) : mix(rose, aqua, smoothstep(2.0, 3.0, x)));
	return c;
}
void fragment() {
	vec3 view = normalize(v_world - (CAMERA_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float facing = abs(dot(v_n, view));
	float hue = dot(v_n, vec3(0.35, 0.55, 0.25)) * 0.8 + facing * 0.5 + v_seed + TIME * 0.04;
	vec3 col = opal(hue);
	vec3 light = normalize(vec3(-0.3, 0.8, 0.5));
	float shade = 0.25 + 0.75 * max(dot(v_n, light), 0.0);
	float rim = pow(1.0 - facing, 3.0);
	float f = flash();
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 20.0) / 40.0, 0.25, 1.0);
	// (deep in the middle, lit through at the edges, a bright glint where a facet catches the light)
	float glint = pow(max(dot(reflect(view, v_n), light), 0.0), 24.0);
	vec3 c = col * (shade * 0.6 + rim * 0.9) + vec3(1.0) * glint * 0.8 + mix(col, hit_color.rgb, f) * rim * f * 1.5;
	ALBEDO = c * fade;
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Crystals"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 10.0
	add_child(mmi)

	# sparkles drifting between them
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = q
	smm.instance_count = SPARKLES
	n = 0
	while n < SPARKLES:
		var p := Vector3(rng.randf_range(-24, 24), rng.randf_range(-8, 12), rng.randf_range(-40, -4))
		if abs(p.x) < 3.5 and abs(p.y) < 3.5 and p.z > -10:
			continue
		smm.set_instance_transform(n, Transform(Basis(), p))
		n += 1
	var spark_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_seed;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash(o.x * 2.3 + o.y * 5.1 + o.z * 8.9);
	VERTEX.y += sin(TIME * 0.3 + v_seed * 30.0) * 0.6;
	VERTEX.x += cos(TIME * 0.25 + v_seed * 17.0) * 0.6;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float glow = pow(clamp(1.0 - d, 0.0, 1.0), 3.0);
	float cr = clamp(1.0 - abs(q.x) * 10.0, 0.0, 1.0) * (1.0 - abs(q.y)) + clamp(1.0 - abs(q.y) * 10.0, 0.0, 1.0) * (1.0 - abs(q.x));
	float tw = pow(0.5 + 0.5 * sin(TIME * (1.5 + v_seed * 3.0) + v_seed * 70.0), 4.0);
	vec3 col = 0.6 + 0.4 * cos(6.28318 * (v_seed + vec3(0.0, 0.33, 0.67)));
	ALBEDO = col * (glow + cr * 0.6) * tw * 1.5 * (1.0 + flash());
}
""")
	var smmi := MultiMeshInstance.new()
	smmi.name = "Sparkles"
	smmi.multimesh = smm
	smmi.material_override = spark_mat
	smmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	smmi.extra_cull_margin = 20.0
	add_child(smmi)
