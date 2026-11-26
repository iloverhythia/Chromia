extends "res://assets/worlds/chromia/chromia_world.gd"

# Pulse Floor: a floor of outlined tiles under the grid that breathes slowly,
# and on every hit a ring of light runs out across it from under the grid.
# One MultiMesh; the waves are worked out in its shader.

const COLS := 30
const ROWS := 28
const STEP := 2.0

func _build():
	var q := QuadMesh.new()
	q.size = Vector2(STEP * 0.92, STEP * 0.92)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = COLS * ROWS
	var flat := Basis(Vector3(1, 0, 0), -PI / 2) # (lying on the floor)
	var n := 0
	for r in ROWS:
		for c in COLS:
			var x = (c - (COLS - 1) * 0.5) * STEP
			var z = 6.0 - r * STEP
			mm.set_instance_transform(n, Transform(flat, Vector3(x, -3.6, z)))
			n += 1
	var mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_d;
void vertex() {
	vec3 o = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_d = length(o.xz - vec2(0.0, -2.0));
}
void fragment() {
	vec2 q = abs(UV * 2.0 - 1.0);
	float e = max(q.x, q.y);
	float edge = smoothstep(0.80, 0.97, e);
	float fill = 0.06;
	float idle = 0.18 + 0.12 * sin(v_d * 0.45 - TIME * 1.2);
	float ring = exp(-pow((v_d - hit_age * 20.0) / 2.2, 2.0)) * exp(-hit_age * 1.1);
	vec3 base = mix(c_lilac.rgb, c_main.rgb, 0.5 + 0.5 * sin(v_d * 0.12 - TIME * 0.3));
	vec3 col = base * (edge + fill) * idle * 2.0 + mix(c_pink.rgb, hit_color.rgb, 0.6) * ring * (edge * 1.6 + 0.35);
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 14.0) / 45.0, 0.0, 1.0);
	ALBEDO = col * fade;
}
""")
	var mmi := MultiMeshInstance.new()
	mmi.name = "Tiles"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 20.0
	add_child(mmi)
