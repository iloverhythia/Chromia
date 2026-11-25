extends "res://assets/worlds/chromia/chromia_world.gd"

# Lilac Orbit: tilted rings circle the grid at their own speeds, each with a
# few glowing moons riding along it. One mesh, turned in its shader.

const RADII := [6.0, 9.5, 13.0, 17.0, 22.0, 28.0]
const SEG := 140

func _build():
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RADII.size():
		var r: float = RADII[i]
		var pts = []
		for s in SEG:
			var a = TAU * float(s) / float(SEG)
			pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
		ribbon(st, pts, 0.10 + r * 0.008, Vector3(0, 0, 1), float(i), true)
		# its moons: small squares on the ring (uv2.y > 1.5: a moon)
		for k in 3:
			var a2 = TAU * (float(k) / 3.0 + float(i) * 0.137)
			var c = Vector3(cos(a2) * r, sin(a2) * r, 0.0)
			var h = 0.35 + r * 0.02
			var corners = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for j in tri:
					var cv: Vector2 = corners[j]
					st.add_uv(Vector2(0.0, float(i)))
					st.add_uv2(Vector2(cv.x * 0.5 + 0.5, cv.y * 0.5 + 2.5))
					st.add_vertex(c + Vector3(cv.x * h, cv.y * h, 0.0))
	var mat := shader_mat(UNIFORMS + """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_idx;
varying vec2 v_uv2;
mat3 rot_x(float a) { return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a))); }
mat3 rot_y(float a) { return mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a))); }
mat3 rot_z(float a) { return mat3(vec3(cos(a), sin(a), 0.0), vec3(-sin(a), cos(a), 0.0), vec3(0.0, 0.0, 1.0)); }
void vertex() {
	float i = UV.y;
	float dir = mod(i, 2.0) < 0.5 ? 1.0 : -1.0;
	float spin = TIME * (0.06 + 0.035 * hash(i + 1.0)) * dir;
	vec3 p = rot_z(spin) * VERTEX;
	p = rot_y(0.5 + hash(i + 7.0) * 1.1 - 0.55) * rot_x(1.15 + hash(i + 3.0) * 0.6 - 0.3 + sin(TIME * 0.05 + i) * 0.08) * p;
	VERTEX = p + vec3(0.0, -1.0, -20.0);
	v_idx = i;
	v_uv2 = UV2;
}
void fragment() {
	float f = flash();
	float dist = length(VERTEX);
	float fade = clamp(1.0 - (dist - 16.0) / 60.0, 0.0, 1.0);
	vec3 col;
	float a;
	if (v_uv2.y > 1.5) {
		vec2 q = vec2(v_uv2.x, v_uv2.y - 2.0) * 2.0 - 1.0;
		float d = length(q);
		a = clamp(1.0 - d, 0.0, 1.0);
		a = a * a * 1.6 + smoothstep(0.35, 0.0, d);
		col = mix(c_pink.rgb, vec3(1.0), 0.25);
	} else {
		a = 1.0 - pow(abs(v_uv2.x * 2.0 - 1.0), 2.0);
		col = mod(v_idx, 3.0) < 0.5 ? c_main.rgb : (mod(v_idx, 3.0) < 1.5 ? c_lilac.rgb : c_pink.rgb);
		a *= 0.55;
	}
	ALBEDO = mix(col, hit_color.rgb, f * 0.5) * a * fade * (1.0 + f * 1.4);
}
""")
	var mi := mesh_instance(st.commit(), mat)
	mi.name = "Orbits"
	add_child(mi)
