extends "res://assets/worlds/chromia/chromia_world.gd"

# Nebula: deep space inside a glowing nebula, clouds of magenta, blue and teal
# gas with dark dust lanes drifting slowly, thousands of stars twinkling, and
# a banded, ringed planet hanging off to the side. A hit makes the gas glow.
# Its own colours (not your colorset).

const STARS := 420

func sky_color() -> Color:
	return Color("#04030c")

func uses_fog() -> bool:
	return false

func _build():
	# the nebula all round (3D value noise, a few octaves, so it has no seam)
	sky_dome("""
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * n3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}
void fragment() {
	vec3 d = normalize(v_dir);
	float t = TIME * 0.012;
	vec3 q = d * 2.2 + vec3(t, t * 0.6, -t * 0.4);
	float warp = fbm(q * 1.3);
	float gas = fbm(q + warp * 1.6);
	float gas2 = fbm(q * 1.7 - warp + vec3(4.0, 1.0, 7.0));
	float dust = smoothstep(0.42, 0.62, fbm(q * 2.4 + vec3(9.0, 3.0, 1.0)));
	vec3 magenta = vec3(0.95, 0.16, 0.58);
	vec3 blue = vec3(0.16, 0.3, 1.0);
	vec3 teal = vec3(0.1, 0.9, 0.78);
	// (which colour the gas is changes across the sky on its own, slowly: blue, magenta, teal)
	float hue = fbm(d * 1.1 + vec3(20.0, 5.0, 11.0) + vec3(t * 0.5));
	vec3 col = mix(blue, magenta, smoothstep(0.38, 0.62, hue));
	col = mix(col, teal, smoothstep(0.55, 0.8, gas2) * 0.75);
	col = mix(col, vec3(1.0, 0.55, 0.3), smoothstep(0.7, 0.9, gas) * 0.35); // (a warm glow where it's thickest)
	float bright = pow(smoothstep(0.3, 0.85, gas), 2.0) * 0.75 + pow(smoothstep(0.5, 0.9, gas2), 3.0) * 0.5;
	bright *= 1.0 - dust * 0.8;
	vec3 space = vec3(0.012, 0.008, 0.03);
	// tiny far stars in the gas itself
	vec3 sp = floor(d * 260.0);
	float star = step(0.9985, h3(sp)) * (0.5 + 0.5 * sin(TIME * 2.0 + h3(sp + 1.0) * 40.0));
	ALBEDO = space + col * bright * (1.0 + flash() * 0.5) + vec3(star) + dither(FRAGCOORD.xy);
}
""")

	# the stars: points of light, some bluish, some golden, twinkling
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = STARS
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var n := 0
	while n < STARS:
		var p := Vector3(rng.randf_range(-45, 45), rng.randf_range(-25, 30), rng.randf_range(-55, -8))
		if abs(p.x) < 4.0 and abs(p.y) < 4.0:
			continue
		mm.set_instance_transform(n, Transform(Basis(), p))
		n += 1
	var star_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_seed;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash(o.x * 3.1 + o.y * 7.7 + o.z * 1.3);
	VERTEX *= 0.6 + pow(v_seed, 3.0) * 3.0;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float core = pow(clamp(1.0 - d, 0.0, 1.0), 3.0);
	float spikes = clamp(1.0 - abs(q.x) * 12.0, 0.0, 1.0) * clamp(1.0 - abs(q.y), 0.0, 1.0) + clamp(1.0 - abs(q.y) * 12.0, 0.0, 1.0) * clamp(1.0 - abs(q.x), 0.0, 1.0);
	float tw = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(TIME * (0.7 + v_seed * 2.5) + v_seed * 60.0), 2.0);
	vec3 col = v_seed < 0.33 ? vec3(0.7, 0.82, 1.0) : (v_seed < 0.66 ? vec3(1.0) : vec3(1.0, 0.85, 0.6));
	ALBEDO = col * (core * 1.6 + spikes * 0.35 * step(0.8, v_seed)) * tw * (1.0 + flash() * 0.8);
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Stars"
	mmi.multimesh = mm
	mmi.material_override = star_mat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 60.0
	add_child(mmi)

	# the planet: bands of gas, lit from one side, a thin blue edge of atmosphere
	var at := Vector3(-17, 8, -44)
	var sphere := SphereMesh.new()
	sphere.radius = 6.0
	sphere.height = 12.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var planet_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded;
varying vec3 v_local;
void vertex() {
	v_local = VERTEX / 6.0;
}
void fragment() {
	vec3 nrm = normalize(v_local);
	float lat = nrm.y + 0.08 * sin(atan(nrm.x, nrm.z) * 3.0 + TIME * 0.05);
	float bands = 0.5 + 0.5 * sin(lat * 22.0) * 0.6 + 0.2 * sin(lat * 57.0 + 1.3);
	vec3 a = vec3(0.78, 0.45, 0.26);
	vec3 b = vec3(0.32, 0.1, 0.2);
	vec3 col = mix(b, a, bands);
	vec3 sun = normalize(vec3(0.8, 0.35, 0.6));
	vec3 wn = normalize((WORLD_MATRIX * vec4(nrm, 0.0)).xyz);
	float lit = smoothstep(-0.15, 0.6, dot(wn, sun));
	vec3 view = normalize((CAMERA_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float rim = pow(1.0 - abs(dot(wn, -view)), 3.0);
	ALBEDO = col * (0.02 + lit * 0.8) + vec3(0.2, 0.75, 1.0) * rim * (0.2 + lit * 0.7);
}
""")
	var planet := mesh_instance(sphere, planet_mat)
	planet.name = "Planet"
	planet.translation = at
	add_child(planet)
	# its rings: a flat band round it, tilted, with gaps
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts = []
	for s in 96:
		var a = TAU * float(s) / 96.0
		pts.append(Vector3(cos(a) * 10.5, 0.0, sin(a) * 10.5))
	ribbon(st, pts, 6.0, Vector3(0, 1, 0), 0.0, true)
	var ring_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float r = UV2.x; // (0 inside, 1 outside)
	float rings = 0.55 + 0.45 * sin(r * 60.0) * sin(r * 13.0 + 1.0);
	float edge = smoothstep(0.0, 0.08, r) * smoothstep(1.0, 0.85, r) * (1.0 - smoothstep(0.42, 0.46, r) * smoothstep(0.52, 0.48, r));
	ALBEDO = mix(vec3(0.9, 0.7, 0.55), vec3(0.6, 0.65, 0.95), r) * rings * edge * 0.45;
}
""")
	var rings := mesh_instance(st.commit(), ring_mat)
	rings.name = "Rings"
	rings.translation = at
	rings.rotation_degrees = Vector3(18, 0, -22)
	add_child(rings)
