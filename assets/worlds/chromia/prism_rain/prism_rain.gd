extends "res://assets/worlds/chromia/chromia_world.gd"

# Prism Rain: thin neon streaks fall all around the grid at their own speeds,
# in your colorset's colour, pink and lilac; a hit makes them flare.
# One MultiMesh: the falling is worked out in its shader.

const COUNT := 420

func _build():
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 6767
	var n := 0
	while n < COUNT:
		var p = Vector3(rng.randf_range(-30, 30), rng.randf_range(-14, 14), rng.randf_range(-60, -2))
		# (none right around the grid, where the notes come)
		if abs(p.x) < 3.5 and abs(p.y) < 3.5 and p.z > -12:
			continue
		mm.set_instance_transform(n, Transform(Basis(), p))
		n += 1
	var mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_seed;
varying vec2 v_uv;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float seed = hash(o.x * 12.9898 + o.z * 78.233);
	float speed = 2.5 + seed * 5.0;
	float y = mod(o.y + 14.0 - TIME * speed, 28.0) - 14.0;
	VERTEX.y += y - o.y;
	VERTEX.y *= 1.0 + seed * 0.8;
	v_seed = seed;
	v_uv = UV;
}
void fragment() {
	vec3 base = v_seed < 0.4 ? c_main.rgb : (v_seed < 0.7 ? c_pink.rgb : c_lilac.rgb);
	float tail = pow(1.0 - v_uv.y, 2.0); // (bright at the bottom, its head)
	float core = 1.0 - abs(v_uv.x * 2.0 - 1.0);
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 15.0) / 55.0, 0.0, 1.0);
	float f = flash();
	ALBEDO = mix(base, hit_color.rgb, f * 0.5) * tail * core * fade * (0.55 + f * 1.6);
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Rain"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 200.0
	add_child(mmi)
