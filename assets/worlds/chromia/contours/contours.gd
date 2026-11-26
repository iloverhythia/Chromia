extends "res://assets/worlds/chromia/chromia_world.gd"

# Contours: the menu's contour lines as a world. Wobbly rings lie on the
# floor and the ceiling around the grid, flowing slowly like the menu's
# pattern; every fourth one is a bright pink major line. They light up on hits.

const LOOPS := 15
const SEG := 120
const CENTER := Vector3(0, 0, -14)

func _build():
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in LOOPS:
		var r = 3.0 + i * 4.6
		var pts = []
		for s in SEG:
			var a = TAU * float(s) / float(SEG)
			pts.append(Vector3(CENTER.x + cos(a) * r, 0.0, CENTER.z + sin(a) * r))
		ribbon(st, pts, 0.10 + r * 0.006 + (0.08 if i % 4 == 0 else 0.0), Vector3.UP, float(i), true)
	var mesh := st.commit()
	var mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float floor_y = -4.0;
uniform float bright = 1.0;
varying float v_idx;
varying float v_edge;
void vertex() {
	vec2 c = vec2(0.0, -14.0);
	vec2 p = VERTEX.xz - c;
	float r = length(p);
	float a = atan(p.y, p.x);
	float idx = UV.y;
	float t = TIME;
	r += (sin(a * 3.0 + t * 0.22 + idx * 0.7) * 0.9 + sin(a * 5.0 - t * 0.15 + idx * 1.3) * 0.45) * (0.4 + r * 0.03);
	VERTEX.xz = c + vec2(cos(a), sin(a)) * r;
	VERTEX.y = floor_y + sin(a * 2.0 + t * 0.1 + idx) * 0.25;
	v_idx = idx;
	v_edge = UV2.x;
}
void fragment() {
	bool major = mod(v_idx, 4.0) < 0.5;
	vec3 base = major ? c_pink.rgb : mix(c_lilac.rgb, c_main.rgb, 0.5);
	float soft = 1.0 - pow(abs(v_edge * 2.0 - 1.0), 2.0);
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 18.0) / 55.0, 0.0, 1.0);
	float f = flash();
	vec3 col = mix(base, hit_color.rgb, f * 0.6) * (major ? 0.9 : 0.45) * (1.0 + f * 1.5) * bright;
	ALBEDO = col * soft * fade;
}
""")
	var floor_lines := mesh_instance(mesh, mat)
	floor_lines.name = "Floor"
	add_child(floor_lines)
	# the ceiling: the same lines, dimmer, higher up
	var mat2: ShaderMaterial = mat.duplicate()
	mat2.set_shader_param("floor_y", 7.0)
	mat2.set_shader_param("bright", 0.45)
	_mats.append(mat2)
	var ceil_lines := mesh_instance(mesh, mat2)
	ceil_lines.name = "Ceiling"
	add_child(ceil_lines)
