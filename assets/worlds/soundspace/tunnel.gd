extends Spatial

# Sound Space Mode's background (scripts/game/SoundSpaceMode.gd): the classic
# Sound Space room. A grid on the floor and the ceiling; both surfaces are a
# dim navy that fades into the dark fog toward the middle of the screen, and
# the grid lines fade out with them.
#
# The numbers are measured from a 1080p recording of Sound Space, in screen
# terms: q = 1 / (pixels from the screen centre, at 1080p) for a point on the
# ceiling or floor. The shader works out q from the camera's field of view so
# the grid lands on the same pixels whatever the FOV.

const H := 7.0          # floor at y = -H, ceiling at +H
const CAM_Z := 3.5      # where the game camera sits
const WIDTH := 400.0
const BEHIND := 10.0
const LENGTH := 120.0
const FOG_COLOR := Color8(10, 8, 26) # same as FOG_COL in the shader

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform float kf = 0.0002;     // 1 / (focal length in 1080p pixels * H)
uniform float cam_z = 3.5;
uniform float px = 1.0;        // screen pixels per 1080p pixel
// screen (sRGB) colours: the fades are measured on screen, so they're mixed
// in sRGB and converted at the end
const vec3 NEAR_COL = vec3(20.0, 16.0, 29.0) / 255.0;
const vec3 FOG_COL = vec3(10.0, 8.0, 26.0) / 255.0;
const vec3 LINE_COL = vec3(117.0, 113.0, 126.0) / 255.0;
uniform bool linear_out = true;
const float CELL_X = 0.354;    // grid cell width / H
const float Q0 = 0.002004;     // first cross line
const float DQ = 0.000466;     // cross line spacing
const float Q_TOP = 0.00185;   // top/bottom edge of the screen
const float Q_FOG = 0.00474;   // surface fully faded into the fog
const float Q_LINES = 0.0049;  // lines fully faded
varying vec3 wpos;
void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float grid_line(float g) {
	float w = max(fwidth(g), 0.00001);
	float d = abs(fract(g - 0.5) - 0.5) / w;
	return 1.0 - smoothstep(0.35 * px, 0.35 * px + 1.0, d);
}
void fragment() {
	float h = abs(wpos.y);
	float q = (cam_z - wpos.z) * kf * (7.0 / max(h, 0.001));
	float lx = grid_line(wpos.x / (CELL_X * h) + 0.5);
	float lz = grid_line((q - Q0) / DQ);
	float fog = clamp((q - Q_TOP) / (Q_FOG - Q_TOP), 0.0, 1.0);
	vec3 surf = mix(NEAR_COL, FOG_COL, fog);
	float fade = clamp((Q_LINES - q) / (Q_LINES - Q_TOP), 0.0, 1.0);
	float line = max(lx, lz) * fade;
	vec3 col = mix(surf, LINE_COL, line);
	if (q <= 0.0) { col = NEAR_COL; } // behind the camera
	ALBEDO = linear_out ? mix(col / 12.92, pow((col + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), col)) : col;
}
"""

var _mats := []

func _ready():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sh := Shader.new()
	sh.code = SHADER
	var z := CAM_Z + BEHIND - LENGTH / 2.0
	_plane(sh, Transform(Basis(), Vector3(0, -H, z)))
	_plane(sh, Transform(Basis(Vector3(0, 0, 1), PI), Vector3(0, H, z)))
	_update()

func _plane(sh: Shader, t: Transform):
	var m := PlaneMesh.new()
	m.size = Vector2(WIDTH, LENGTH)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_param("cam_z", CAM_Z)
	mat.set_shader_param("linear_out", OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3)
	var mi := MeshInstance.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = t
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mats.append(mat)

func _process(_d):
	_update()

var _last := Vector2.ZERO
func _update():
	var cam := get_viewport().get_camera()
	var fov: float = cam.fov if cam != null else 75.0
	var vh: float = get_viewport().get_visible_rect().size.y
	if cam != null and cam.keep_aspect == Camera.KEEP_WIDTH:
		var vs := get_viewport().get_visible_rect().size
		# horizontal fov: turn it into the vertical one
		fov = rad2deg(2.0 * atan(tan(deg2rad(fov) / 2.0) * vs.y / max(vs.x, 1.0)))
	var key := Vector2(fov, vh)
	if key == _last:
		return
	_last = key
	var f := 540.0 / tan(deg2rad(clamp(fov, 1.0, 179.0)) / 2.0)
	for m in _mats:
		m.set_shader_param("kf", 1.0 / (f * H))
		m.set_shader_param("px", max(vh / 1080.0, 0.5))
