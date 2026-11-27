extends "res://assets/worlds/chromia/chromia_world.gd"

# Molten Core: a plain of cooled black rock split by glowing lava cracks that
# slowly churn, under a smoky sky lit red from the horizon. Embers drift up
# all around. A hit makes the lava flare and a wave of heat run out across it.
# Its own fiery reds, oranges and yellows (not your colorset).

const EMBERS := 320

func sky_color() -> Color:
	return Color("#0c0302")

func uses_fog() -> bool:
	return false

# the sky looking in a direction: smoke over a glowing horizon (the floor fades into it too)
const SKY := """
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
vec3 sky(vec3 d, float t) {
	float up = d.y;
	vec3 glow = vec3(0.55, 0.09, 0.012);
	vec3 col = mix(vec3(0.02, 0.004, 0.002), vec3(0.004, 0.001, 0.001), smoothstep(0.0, 0.5, up));
	col += glow * exp(-abs(up - 0.01) * 14.0) * 0.45;
	// drifting smoke, lit from below: dark clouds against the glow
	vec2 p = vec2(atan(d.x, -d.z) * 3.0 + t * 0.03, up * 7.0);
	float s = n2(p * 2.0) * 0.6 + n2(p * 4.3 + vec2(t * 0.05, 0.0)) * 0.4;
	col += glow * pow(s, 3.0) * 0.25 * smoothstep(0.45, 0.0, up) * smoothstep(-0.1, 0.03, up);
	col *= 1.0 - smoothstep(0.45, 0.75, s) * 0.6 * smoothstep(0.35, 0.05, up);
	return col;
}
"""

func _build():
	sky_dome(SKY + """
void fragment() {
	ALBEDO = sky(normalize(v_dir), TIME) * (1.0 + flash() * 0.3) + dither(FRAGCOORD.xy);
}
""")

	# the lava plain: cells of rock, glowing at their edges (cellular noise, churning slowly)
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 150)
	var floor_mat := shader_mat(UNIFORMS + SKY + """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 v_world;
void vertex() {
	v_world = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
vec2 cell_point(vec2 c, float t) {
	vec2 h = vec2(fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453), fract(sin(dot(c, vec2(269.5, 183.3))) * 43758.5453));
	return 0.5 + 0.38 * sin(t * 0.25 + 6.2831 * h);
}
void fragment() {
	vec2 p = v_world.xz * 0.55;
	p += 0.35 * vec2(sin(p.y * 1.7 + TIME * 0.2), cos(p.x * 1.3 - TIME * 0.15)); // (no two cracks alike)
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + cell_point(i + g, TIME) - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	float edge = sqrt(d2) - sqrt(d1); // (0 on a crack)
	float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + p.x * 0.7 + p.y * 0.5);
	float wave = exp(-pow((length(v_world.xz - vec2(0.0, -2.0)) - hit_age * 16.0) / 3.0, 2.0)) * exp(-hit_age * 1.0);
	float heat = exp(-edge * 16.0) * pulse * (1.0 + wave * 2.5 + flash() * 0.8);
	float warm = exp(-edge * 4.0) * 0.12; // (the rock glows a little near a crack)
	vec3 rock = vec3(0.008, 0.003, 0.002) + vec3(0.02, 0.005, 0.002) * (1.0 - sqrt(d1));
	vec3 lava = mix(vec3(0.55, 0.03, 0.0), vec3(1.0, 0.32, 0.02), clamp(heat, 0.0, 1.0));
	lava = mix(lava, vec3(1.0, 0.85, 0.4), clamp(heat - 1.0, 0.0, 1.0));
	vec3 col = rock + lava * heat + vec3(0.5, 0.06, 0.0) * warm;
	float dist = length(v_world.xz - vec2(0.0, 3.0));
	float fade = clamp(1.0 - (dist - 12.0) / 60.0, 0.0, 1.0);
	vec3 far = sky(normalize((CAMERA_MATRIX * vec4(VERTEX, 0.0)).xyz), TIME);
	ALBEDO = mix(far, col, fade);
}
""")
	var fl := mesh_instance(plane, floor_mat)
	fl.name = "Lava"
	fl.translation = Vector3(0, -3.6, -30)
	add_child(fl)

	# embers, rising and swaying, cooling from yellow to red as they go
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = EMBERS
	var rng := RandomNumberGenerator.new()
	rng.seed = 1666
	var n := 0
	while n < EMBERS:
		var p := Vector3(rng.randf_range(-28, 28), rng.randf_range(-3.6, 14), rng.randf_range(-50, -2))
		if abs(p.x) < 3.0 and abs(p.y) < 3.0 and p.z > -10:
			continue
		mm.set_instance_transform(n, Transform(Basis(), p))
		n += 1
	var ember_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_seed;
varying float v_life;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float seed = hash(o.x * 5.3 + o.z * 9.7);
	float speed = 0.9 + seed * 1.8;
	float y = mod(o.y + 3.6 + TIME * speed, 17.6);
	v_life = y / 17.6;
	VERTEX.y += (y - 3.6) - o.y;
	VERTEX.x += sin(TIME * (0.6 + seed) + seed * 20.0) * 0.8 * v_life;
	VERTEX *= 0.6 + seed * 1.2;
	v_seed = seed;
}
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float core = clamp(1.0 - d, 0.0, 1.0);
	core = core * core;
	float flick = 0.7 + 0.3 * sin(TIME * (8.0 + v_seed * 9.0) + v_seed * 50.0);
	vec3 col = mix(vec3(1.0, 0.85, 0.35), vec3(1.0, 0.2, 0.03), v_life);
	float fade = (1.0 - v_life) * smoothstep(0.0, 0.05, v_life);
	float dist = length(VERTEX);
	float far = clamp(1.0 - (dist - 12.0) / 45.0, 0.0, 1.0);
	ALBEDO = col * core * flick * fade * far * 1.6 * (1.0 + flash() * 1.2);
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Embers"
	mmi.multimesh = mm
	mmi.material_override = ember_mat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40.0
	add_child(mmi)
