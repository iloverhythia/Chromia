extends Spatial

# Sound Space Mode's background (scripts/game/SoundSpaceMode.gd): the classic
# Sound Space room, a dark navy tunnel with grid lines on the floor, ceiling and
# both walls, fading into the distance.

const W := 21.0        # half width (walls at x = -W, +W)
const H := 12.0         # half height (floor at y = -H, ceiling at +H)
const NEAR := 6.0      # starts a bit behind the camera
const LENGTH := 120.0
const SPACING := 7.0

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 line_color : hint_color = vec4(0.6, 0.6, 0.7, 0.6);
uniform vec2 size = vec2(10.0, 10.0);
uniform float spacing = 2.6;
uniform float fade_distance = 80.0;
void fragment() {
	vec2 g = (UV - 0.5) * size / spacing + 0.5;
	vec2 w = fwidth(g);
	vec2 f = abs(fract(g - 0.5) - 0.5) / max(w, vec2(0.0001));
	float line = 1.0 - smoothstep(0.0, 1.2, min(f.x, f.y));
	float fade = clamp(1.0 - (-VERTEX.z) / fade_distance, 0.0, 1.0);
	ALBEDO = line_color.rgb;
	ALPHA = line * line_color.a * fade * fade;
}
"""

func _ready():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.03, 0.085)
	env.ambient_light_color = Color(1, 1, 1)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sh := Shader.new()
	sh.code = SHADER
	var z := NEAR - LENGTH / 2.0
	# floor and ceiling
	_plane(sh, Vector2(W * 2.0, LENGTH), Transform(Basis(), Vector3(0, -H, z)))
	_plane(sh, Vector2(W * 2.0, LENGTH), Transform(Basis(Vector3(0, 0, 1), PI), Vector3(0, H, z)))
	# walls
	_plane(sh, Vector2(H * 2.0, LENGTH), Transform(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3(-W, 0, z)))
	_plane(sh, Vector2(H * 2.0, LENGTH), Transform(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(W, 0, z)))

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
