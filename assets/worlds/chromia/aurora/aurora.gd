extends "res://assets/worlds/chromia/chromia_world.gd"

# Aurora: curtains of light wave slowly above and behind the grid, from your
# colorset's colour at their foot to pink and lilac at the top, under a sky
# of twinkling stars. A hit makes them flare.

const CURTAINS := 4
const SEG := 150
const STARS := 180

func _build():
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in CURTAINS:
		var z = -22.0 - i * 7.0
		var base = 2.5 + i * 1.6
		var h = 7.0 + i * 1.5
		var pts = []
		for s in SEG + 1:
			var x = -45.0 + 90.0 * float(s) / float(SEG)
			pts.append(Vector3(x, base + h * 0.5, z + sin(x * 0.07 + i) * 4.0))
		ribbon(st, pts, h, Vector3(0, 0, 1), float(i), false)
	var mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_idx;
varying float v_u;
varying float v_h;
void vertex() {
	float i = UV.y;
	float t = TIME;
	v_h = UV2.x; // (0 at the top, 1 at the foot)
	VERTEX.z += sin(VERTEX.x * 0.12 + t * 0.35 + i * 1.7) * 2.2 + sin(VERTEX.x * 0.31 - t * 0.21 + i) * 0.8;
	VERTEX.x += sin(VERTEX.y * 0.2 + t * 0.4 + i) * 0.6 * (1.0 - v_h);
	v_idx = i;
	v_u = UV.x;
}
void fragment() {
	float f = flash();
	float foot = v_h;
	float glow = pow(foot, 2.2) * 0.9 + 0.12 * foot;
	float rays = 0.55 + 0.45 * sin(v_u * 240.0 + TIME * 0.6 + v_idx * 3.0) * sin(v_u * 37.0 - TIME * 0.25);
	vec3 top = mod(v_idx, 2.0) < 0.5 ? c_pink.rgb : c_lilac.rgb;
	vec3 col = mix(top, c_main.rgb, foot);
	float ends = smoothstep(0.0, 0.12, v_u) * smoothstep(1.0, 0.88, v_u);
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 25.0) / 60.0, 0.15, 1.0);
	ALBEDO = mix(col, hit_color.rgb, f * 0.45) * glow * rays * ends * fade * (0.7 + f * 1.3);
}
""")
	var mi := mesh_instance(st.commit(), mat)
	mi.name = "Curtains"
	add_child(mi)
	# the stars
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = STARS
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for n in STARS:
		mm.set_instance_transform(n, Transform(Basis(), Vector3(rng.randf_range(-60, 60), rng.randf_range(4, 30), rng.randf_range(-70, -25))))
	var smat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_seed;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash(o.x * 3.1 + o.y * 7.7 + o.z);
	VERTEX *= 1.0 + v_seed * 2.0;
}
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float tw = 0.4 + 0.6 * pow(0.5 + 0.5 * sin(TIME * (0.8 + v_seed * 2.0) + v_seed * 40.0), 3.0);
	ALBEDO = mix(vec3(1.0), c_lilac.rgb, v_seed) * clamp(1.0 - d, 0.0, 1.0) * tw * (1.0 + flash());
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Stars"
	mmi.multimesh = mm
	mmi.material_override = smat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 50.0
	add_child(mmi)
