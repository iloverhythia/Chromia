extends Spatial

# Sound Space Mode's background (scripts/game/SoundSpaceMode.gd): the classic
# Sound Space room, a dark navy space with a grid on the floor and the ceiling
# that fades into the dark in the distance.

const H := 7.0         # floor at y = -H, ceiling at +H
const WIDTH := 240.0
const NEAR := 10.0     # starts a bit behind the camera
const LENGTH := 140.0
const SPACING := 3.2

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 line_color : hint_color = vec4(0.5, 0.48, 0.6, 1.0);
uniform vec2 size = vec2(10.0, 10.0);
uniform float spacing = 3.2;
uniform float fade_distance = 24.0;
void fragment() {
	vec2 g = (UV - 0.5) * size / spacing + 0.5;
	vec2 w = fwidth(g);
	vec2 f = abs(fract(g - 0.5) - 0.5) / max(w, vec2(0.0001));
	float line = 1.0 - smoothstep(0.0, 1.1, min(f.x, f.y));
	float fade = clamp(1.0 - (-VERTEX.z) / fade_distance, 0.0, 1.0);
	ALBEDO = line_color.rgb;
	ALPHA = line * line_color.a * fade * fade;
}
"""

func _ready():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.038, 0.03, 0.09)
	env.ambient_light_color = Color(1, 1, 1)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sh := Shader.new()
	sh.code = SHADER
	var z := NEAR - LENGTH / 2.0
	_plane(sh, Vector2(WIDTH, LENGTH), Transform(Basis(), Vector3(0, -H, z)))
	_plane(sh, Vector2(WIDTH, LENGTH), Transform(Basis(Vector3(0, 0, 1), PI), Vector3(0, H, z)))

func _plane(sh: Shader, size: Vector2, t: Transform):
	var m := PlaneMesh.new()
	m.size = size
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_param("size", size)
	mat.set_shader_param("spacing", SPACING)
	var mi := MeshInstance.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = t
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
