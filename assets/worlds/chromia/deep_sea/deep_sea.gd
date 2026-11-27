extends "res://assets/worlds/chromia/chromia_world.gd"

# Deep Sea: the bottom of the ocean. Light from the surface far above comes
# down in slow shafts and ripples over the sand in moving caustics, bubbles
# rise all around, and the water fades from turquoise up high to the dark of
# the deep. A hit sends a ripple of light out across the floor.
# Its own blues and teals (not your colorset); the ripple is the note's colour.

const SHAFTS := 14
const BUBBLES := 260

# the water's colour looking in a direction (the sky and the floor's distance both use it)
const WATER := """
vec3 water(vec3 d, float t) {
	float up = d.y;
	vec3 col = mix(vec3(0.004, 0.02, 0.05), vec3(0.01, 0.12, 0.2), smoothstep(-0.5, 0.15, up));
	col = mix(col, vec3(0.04, 0.34, 0.42), smoothstep(0.15, 0.85, up));
	// the surface's light, wavering
	float a = atan(d.x, -d.z);
	float rays = pow(0.5 + 0.5 * sin(a * 23.0 + sin(t * 0.4 + a * 3.0) * 2.0), 6.0);
	col += vec3(0.2, 0.7, 0.75) * rays * smoothstep(0.1, 0.9, up) * smoothstep(0.97, 0.8, up) * 0.35;
	float shimmer = 0.5 + 0.5 * sin(d.x * 12.0 + t * 0.7 + sin(d.z * 9.0 + t * 0.5) * 1.5);
	col += vec3(0.25, 0.8, 0.85) * shimmer * smoothstep(0.6, 1.0, up) * 0.08;
	return col;
}
"""

func sky_color() -> Color:
	return Color("#020a16")

func uses_fog() -> bool:
	return false

func _build():
	# the water all round: lighter towards the surface, with the light moving on it
	sky_dome(WATER + """
void fragment() {
	ALBEDO = water(normalize(v_dir), TIME) * (1.0 + flash() * 0.25) + dither(FRAGCOORD.xy);
}
""")

	# the sea floor, with caustics (the light through the waves above)
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	var floor_mat := shader_mat(UNIFORMS + WATER + """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 v_world;
void vertex() {
	v_world = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float caustic(vec2 uv, float t) {
	vec2 p = mod(uv * 6.28318, 6.28318) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 4; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	return pow(abs(c), 8.0);
}
void fragment() {
	vec2 xz = v_world.xz;
	float dist = length(xz - vec2(0.0, 3.0));
	float c = caustic(xz * 0.05, TIME * 0.35);
	vec3 sand = vec3(0.02, 0.07, 0.1);
	vec3 light = vec3(0.25, 0.95, 0.9);
	float ring = exp(-pow((length(xz - vec2(0.0, -2.0)) - hit_age * 18.0) / 2.0, 2.0)) * exp(-hit_age * 1.2);
	vec3 col = sand + light * c * 0.55 + hit_color.rgb * ring * 0.9;
	float fade = clamp(1.0 - (dist - 10.0) / 55.0, 0.0, 1.0);
	vec3 far = water(normalize((CAMERA_MATRIX * vec4(VERTEX, 0.0)).xyz), TIME);
	ALBEDO = mix(far, col * (1.0 + flash() * 0.6), fade);
}
""")
	var fl := mesh_instance(plane, floor_mat)
	fl.name = "Floor"
	fl.translation = Vector3(0, -3.6, -30)
	add_child(fl)

	# the light shafts: soft slanted bands from far above, swaying slowly
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4040
	for i in SHAFTS:
		var x := rng.randf_range(-28, 28)
		if abs(x) < 4.0:
			x += sign(x + 0.01) * 5.0
		var z := rng.randf_range(-48, -12)
		var lean := rng.randf_range(-0.25, 0.25)
		var top := Vector3(x + lean * 30.0, 30.0, z)
		var bottom := Vector3(x, -3.6, z)
		ribbon(st, [top, bottom], rng.randf_range(1.5, 4.5), Vector3(0, 0, 1), float(i), false)
	var shaft_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_idx;
varying vec2 v_uv;
void vertex() {
	v_idx = UV.y;
	v_uv = vec2(UV2.x, UV.x);
	VERTEX.x += sin(TIME * 0.25 + v_idx * 1.9) * 1.2 * (1.0 - UV.x);
}
void fragment() {
	float across = 1.0 - abs(v_uv.x * 2.0 - 1.0);
	across = across * across;
	float down = (1.0 - v_uv.y) * smoothstep(0.0, 0.35, v_uv.y); // (bright high up, fading in from nothing at its top end)
	float breathe = 0.6 + 0.4 * sin(TIME * (0.3 + hash(v_idx) * 0.4) + v_idx * 2.3);
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 15.0) / 50.0, 0.0, 1.0);
	vec3 col = mix(vec3(0.15, 0.8, 0.85), vec3(0.55, 1.0, 0.95), hash(v_idx + 4.0));
	ALBEDO = col * across * (0.15 * smoothstep(0.0, 0.35, v_uv.y) + 1.4 * down) * breathe * fade * 0.22 * (1.0 + flash() * 1.5);
}
""")
	var shafts := mesh_instance(st.commit(), shaft_mat)
	shafts.name = "Shafts"
	add_child(shafts)

	# bubbles, rising and wobbling
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = BUBBLES
	var n := 0
	while n < BUBBLES:
		var p := Vector3(rng.randf_range(-26, 26), rng.randf_range(-4, 16), rng.randf_range(-45, -3))
		if abs(p.x) < 3.0 and abs(p.y) < 3.0 and p.z > -10:
			continue
		mm.set_instance_transform(n, Transform(Basis(), p))
		n += 1
	var bub_mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_seed;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float seed = hash(o.x * 3.7 + o.z * 11.1);
	float speed = 0.8 + seed * 1.6;
	float y = mod(o.y + 4.0 + TIME * speed, 20.0) - 4.0;
	VERTEX.y += y - o.y;
	VERTEX.x += sin(TIME * 2.0 + seed * 30.0) * 0.15;
	VERTEX *= 0.5 + seed * 1.3;
	v_seed = seed;
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float rim = smoothstep(0.65, 0.85, d) * smoothstep(1.0, 0.88, d);
	float shine = smoothstep(0.3, 0.0, length(q - vec2(-0.35, -0.35)));
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 12.0) / 40.0, 0.0, 1.0);
	ALBEDO = vec3(0.6, 0.95, 1.0) * (rim * 0.7 + shine * 0.9) * fade * (1.0 + flash());
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Bubbles"
	mmi.multimesh = mm
	mmi.material_override = bub_mat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40.0
	add_child(mmi)
