extends Spatial

# The base of the Chromia worlds (Contours, Prism Rain, Lilac Orbit, Aurora,
# Pulse Floor): the look of Neon Corners and the menu, dark with neon lines
# in your colorset's first colour and Chromia's pink and lilac, fog into the
# distance, a flash on every hit, and glow when it's on (Settings).
#
# Kept light for headsets and phones: each world is one to three meshes,
# made once when the song loads, and moves in its shader; the script only
# passes the time since the last hit (two numbers a frame).
# (In VR with Simple background, songload.gd puts VOID in their place.)

const PINK := Color("#ff739e")
const LILAC := Color("#b57bff")
const PURPLE := Color("#75336b")
const BG := Color("#0b0612")

var main_color := LILAC # (the colorset's first colour)
var hit_color := PINK
var _hit_at := -100.0
var _mats := [] # ShaderMaterials told about hits

func _ready():
	var cs = Rhythia.selected_colorset
	if cs != null and cs.get("colors") is Array and not cs.colors.empty():
		main_color = cs.colors[0]
	hit_color = main_color
	_make_env()
	_build()
	# (no Game node when it is the VR menu's environment)
	var game = get_parent().get_node_or_null("Game")
	if game != null and game.has_signal("hit"):
		game.connect("hit", self, "_on_hit")

# the world's own meshes (each world's script)
func _build():
	pass

func _make_env():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.background_energy = 0.0
	env.ambient_light_color = Color(0.08, 0.06, 0.1)
	env.fog_enabled = true
	env.fog_color = BG
	env.fog_depth_begin = 22.0
	env.fog_depth_end = 70.0
	env.fog_depth_curve = 0.6
	if Rhythia.glow > 0:
		env.glow_enabled = true
		env.glow_intensity = Rhythia.glow
		env.glow_strength = 1
		env.glow_bloom = Rhythia.bloom
		env.glow_blend_mode = 1
		env.glow_hdr_scale = 1.72
		env.glow_high_quality = true
		env.glow_bicubic_upscale = true
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

func _on_hit(col = null):
	_hit_at = OS.get_ticks_msec() / 1000.0
	if col is Color:
		hit_color = col

func _process(_delta):
	var age: float = OS.get_ticks_msec() / 1000.0 - _hit_at
	for m in _mats:
		m.set_shader_param("hit_age", age)
		m.set_shader_param("hit_color", hit_color)

# a ShaderMaterial for this world's code, with the colours and the hit filled in
func shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	# (shader_type and render_mode must come first: the shared UNIFORMS go after them)
	var head := ""
	var rest := ""
	for line in code.split("\n"):
		if line.begins_with("shader_type") or line.begins_with("render_mode"):
			head += line + "\n"
		else:
			rest += line + "\n"
	sh.code = head + rest
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_param("c_main", main_color)
	m.set_shader_param("c_pink", PINK)
	m.set_shader_param("c_lilac", LILAC)
	m.set_shader_param("hit_age", 100.0)
	m.set_shader_param("hit_color", main_color)
	_mats.append(m)
	return m

# the uniforms every world's shader has (put at the top of its code)
const UNIFORMS := """
uniform vec4 c_main : hint_color;
uniform vec4 c_pink : hint_color;
uniform vec4 c_lilac : hint_color;
uniform vec4 hit_color : hint_color;
uniform float hit_age = 100.0;
float flash() { return exp(-hit_age * 5.0); }
float hash(float n) { return fract(sin(n) * 43758.5453); }
"""

# a band that loops (or a line when open) as a triangle strip: points [Vector3],
# its width, the colour of each point; uv.x along it (0..1), uv.y its index
static func ribbon(st: SurfaceTool, pts: Array, width: float, up: Vector3, index: float, closed: bool):
	var n := pts.size()
	var last := n if closed else n - 1
	for i in range(last):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % n]
		var side := (b - a).cross(up).normalized() * width * 0.5
		var u0 := float(i) / float(last)
		var u1 := float(i + 1) / float(last)
		for v in [[a - side, Vector2(u0, index), 0.0], [a + side, Vector2(u0, index), 1.0], [b + side, Vector2(u1, index), 1.0],
				[a - side, Vector2(u0, index), 0.0], [b + side, Vector2(u1, index), 1.0], [b - side, Vector2(u1, index), 0.0]]:
			st.add_uv(v[1])
			st.add_uv2(Vector2(v[2], 0.0))
			st.add_vertex(v[0])

static func mesh_instance(mesh: Mesh, mat: Material) -> MeshInstance:
	var mi := MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0 # (the shaders move the vertices: never culled away)
	return mi
