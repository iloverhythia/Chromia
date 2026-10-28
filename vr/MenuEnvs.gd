extends Spatial

# The VR menu's surroundings (Settings > VR > Menu environment).
#
#  - "classic": the old room (dark, the logo and the floating avatar), without
#    the black pillars that got in the way of your view
#  - five built-in places made here from simple shapes and shaders, cheap
#    enough for the Meta Quest: Deep Space, Synthwave, Sunset Ocean, Pastel
#    Clouds and Neon City
#  - "bg:<id>": any background from the background list (the song
#    backgrounds, the Roblox spaces, your own custom ones), placed around you
#    the way it is in songs
#
# vrmenu.gd adds one of these to the menu (MenuEnvs.make) and swaps it when
# the setting changes. Game units are 2 per metre; the menu screen floats
# about 3 units in front of your eyes, which are kept near y = 2.75. The floor
# of the built-in places sits 1.6 m (3.2 units) below your eyes.

const BUILT_IN := [
	["classic", "Classic"],
	["space", "Deep Space"],
	["synthwave", "Synthwave"],
	["ocean", "Sunset Ocean"],
	["clouds", "Pastel Clouds"],
	["city", "Neon City"],
]
const EYE_TO_FLOOR := 3.2
const DOME_R := 90.0 # inside the VR camera's 100 unit far plane

var id := "classic"
var _floor: Spatial = null # follows your eye height
var _spin := [] # [node, radians per second]
var _cars := [] # Neon City's flying lights: [node, radius, height, speed, angle]

static func name_of(env_id: String) -> String:
	for b in BUILT_IN:
		if b[0] == env_id:
			return b[1]
	if env_id.begins_with("bg:"):
		var w = Rhythia.registry_world.get_item(env_id.substr(3)) if Rhythia.registry_world else null
		return ("Background: " + w.name) if w else "Background"
	return "Classic"

static func is_valid(env_id: String) -> bool:
	for b in BUILT_IN:
		if b[0] == env_id:
			return true
	return env_id.begins_with("bg:") and env_id.length() > 3

# A new environment node for `env_id` (null for "classic", which is the menu
# scene's own nodes).
static func make(env_id: String) -> Spatial:
	if env_id == "classic" or not is_valid(env_id):
		return null
	var e = load("res://vr/MenuEnvs.gd").new()
	e.name = "MenuEnv"
	e.id = env_id
	if env_id.begins_with("bg:"):
		if not e._build_background(env_id.substr(3)):
			e.free()
			return null
	else:
		e._build(env_id)
	return e

func _ready():
	set_process(true)

func _process(delta):
	# the floor stays 1.6 m under your eyes (they move when you recenter)
	if _floor != null and Rhythia.vr_player != null and is_instance_valid(Rhythia.vr_player):
		var o = Rhythia.vr_player.get("origin")
		if o is Spatial and o.is_inside_tree():
			var y: float = o.global_transform.origin.y - EYE_TO_FLOOR
			if abs(_floor.transform.origin.y - y) > 0.01:
				_floor.transform.origin.y = y
	for s in _spin:
		if is_instance_valid(s[0]):
			s[0].rotate_y(s[1] * delta)
	for c in _cars:
		var n: Spatial = c[0]
		if not is_instance_valid(n):
			continue
		c[4] += c[3] * delta
		n.transform.origin = Vector3(cos(c[4]) * c[1], c[2], sin(c[4]) * c[1])
		n.rotation = Vector3(0, -c[4] + (PI if c[3] > 0 else 0.0), 0)

# --- a song background ---------------------------------------------------------
func _build_background(world_id: String) -> bool:
	var w = Rhythia.registry_world.get_item(world_id) if Rhythia.registry_world else null
	if w == null:
		return false
	var path: String = load("res://scripts/game/SoundSpaceMode.gd").space_path(w.path)
	var scene = load(path)
	Rhythia.keep_deps(path, "world")
	if not (scene is PackedScene):
		Rhythia.trail("VR menu: background %s didn't load" % world_id)
		return false
	var inst = scene.instance()
	inst.name = "Space"
	# where it is in songs: the grid (the world's centre) in front of you at
	# the grid distance, at eye height
	inst.transform.origin = Vector3(0, 2.75, -Rhythia.vr_grid_distance * 2.0)
	add_child(inst)
	return true

# --- shared shader parts -------------------------------------------------------
const NOISE := """
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}
float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}
// little points of light on the sky: `scale` cells around the sphere, `chance` of a star in each
float stars(vec3 d, float scale, float chance, float t) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h < 1.0 - chance) { return 0.0; }
	vec3 at = vec3(hash13(c + 7.1), hash13(c + 3.7), hash13(c + 9.3)) * 0.6 + 0.2;
	float r = length(fract(p) - at);
	float tw = 0.65 + 0.35 * sin(t * (1.5 + h * 3.0) + h * 40.0);
	return smoothstep(0.16, 0.0, r) * tw;
}
"""

const DOME_HEAD := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
varying vec3 dir;
void vertex() {
	dir = VERTEX;
}
"""

const WORLD_HEAD := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
varying vec3 wpos;
void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
"""

func _mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _dome(fragment: String):
	var mi := MeshInstance.new()
	var s := SphereMesh.new()
	s.radius = DOME_R
	s.height = DOME_R * 2.0
	s.radial_segments = 32
	s.rings = 16
	mi.mesh = s
	mi.material_override = _mat(DOME_HEAD + NOISE + fragment)
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.name = "Sky"
	add_child(mi)

func _env(bg: Color, glow: bool):
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.glow_enabled = glow
	e.glow_intensity = 0.9
	e.glow_strength = 1.0
	e.glow_hdr_threshold = 0.9
	we.environment = e
	we.name = "WorldEnvironment"
	add_child(we)

func _floor_node() -> Spatial:
	_floor = Spatial.new()
	_floor.name = "Floor"
	_floor.transform.origin.y = 2.75 - EYE_TO_FLOOR
	add_child(_floor)
	return _floor

func _plane(parent: Node, size: float, code: String, y: float = 0.0, subdiv: int = 0) -> MeshInstance:
	var mi := MeshInstance.new()
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	p.subdivide_width = subdiv
	p.subdivide_depth = subdiv
	mi.mesh = p
	mi.material_override = _mat(code)
	mi.transform.origin.y = y
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# a round platform to stand on: a disc with a glowing rim
func _platform(parent: Node, radius: float, top: Color, rim: Color):
	var mi := MeshInstance.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius * 0.92
	c.height = 0.25
	c.radial_segments = 48
	c.rings = 1
	mi.mesh = c
	mi.transform.origin.y = -0.125
	mi.material_override = _mat(WORLD_HEAD + """
uniform vec3 top_col;
uniform vec3 rim_col;
uniform float radius;
uniform vec3 centre;
void fragment() {
	float r = length(wpos.xz - centre.xz) / radius;
	float rim = smoothstep(0.86, 0.99, r);
	float rings = smoothstep(0.455, 0.49, abs(fract(r * 4.0) - 0.5)) * 0.35 * (1.0 - rim);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.6);
	ALBEDO = top_col + rim_col * (rim * 1.2 * pulse + rings);
}
""")
	mi.material_override.set_shader_param("top_col", Vector3(top.r, top.g, top.b))
	mi.material_override.set_shader_param("rim_col", Vector3(rim.r, rim.g, rim.b))
	mi.material_override.set_shader_param("radius", radius)
	mi.material_override.set_shader_param("centre", Vector3.ZERO)
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _sphere(parent: Node, pos: Vector3, r: float, code: String, segs: int = 24) -> MeshInstance:
	var mi := MeshInstance.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	mi.mesh = s
	mi.material_override = _mat(code)
	mi.transform.origin = pos
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build(env_id: String):
	match env_id:
		"space": _build_space()
		"synthwave": _build_synthwave()
		"ocean": _build_ocean()
		"clouds": _build_clouds()
		"city": _build_city()

# --- Deep Space: stars, a purple and blue nebula, a ringed planet ---------------
func _build_space():
	_env(Color(0.01, 0.008, 0.02), true)
	_dome("""
void fragment() {
	vec3 d = normalize(dir);
	float a = TIME * 0.006;
	d = vec3(cos(a) * d.x - sin(a) * d.z, d.y, sin(a) * d.x + cos(a) * d.z);
	vec3 col = vec3(0.008, 0.006, 0.02);
	float n = fbm(d * 2.2 + vec3(3.1, 0.0, 1.7));
	float n2 = fbm(d * 4.5 + vec3(5.2, 1.3, 2.1));
	vec3 neb = mix(vec3(0.32, 0.06, 0.42), vec3(0.04, 0.18, 0.5), n2);
	col += neb * smoothstep(0.42, 0.82, n) * 0.85;
	col += vec3(0.9, 0.5, 0.8) * smoothstep(0.7, 0.95, n2) * smoothstep(0.5, 0.8, n) * 0.35;
	col += vec3(1.0, 0.95, 0.9) * stars(d, 90.0, 0.06, TIME);
	col += vec3(0.8, 0.85, 1.0) * stars(d, 220.0, 0.05, TIME) * 0.7;
	ALBEDO = col;
}
""")
	var fl := _floor_node()
	_platform(fl, 2.6, Color(0.04, 0.03, 0.07), Color(0.75, 0.35, 1.0))
	# the planet, lit from one side, with a tilted ring
	var planet := Spatial.new()
	planet.transform.origin = Vector3(-38, 16, -66)
	add_child(planet)
	_sphere(planet, Vector3.ZERO, 11.0, WORLD_HEAD + NOISE + """
uniform vec3 centre;
void fragment() {
	vec3 n = normalize(wpos - centre);
	float lit = clamp(dot(n, normalize(vec3(0.8, 0.3, 0.6))), 0.0, 1.0);
	float bands = fbm(vec3(n.y * 9.0, n.x * 0.6 + TIME * 0.01, n.z * 0.6));
	vec3 base = mix(vec3(0.85, 0.45, 0.7), vec3(0.35, 0.25, 0.75), bands);
	float rim = pow(1.0 - abs(dot(n, normalize(-centre))), 3.0);
	ALBEDO = base * (0.08 + 0.92 * lit) + vec3(0.6, 0.4, 1.0) * rim * 0.4;
}
""", 32).material_override.set_shader_param("centre", planet.transform.origin)
	var ring := MeshInstance.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 22.0
	rm.bottom_radius = 22.0
	rm.height = 0.05
	rm.radial_segments = 64
	rm.rings = 1
	ring.mesh = rm
	ring.material_override = _mat("""
shader_type spatial;
render_mode unshaded, shadows_disabled, blend_add, cull_disabled;
varying vec3 wpos;
void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
uniform vec3 centre;
void fragment() {
	float r = length(wpos - centre) / 22.0;
	float band = smoothstep(0.55, 0.6, r) * smoothstep(1.0, 0.92, r);
	float lines = 0.6 + 0.4 * sin(r * 90.0);
	ALBEDO = vec3(0.7, 0.55, 0.9) * band * lines * 0.55;
}
""")
	ring.material_override.set_shader_param("centre", planet.transform.origin)
	ring.rotation_degrees = Vector3(18, 0, -24)
	ring.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	planet.add_child(ring)
	_spin.append([planet, 0.02])

# --- Synthwave: a neon grid running to a striped sun and purple mountains ------
const SYNTH_SKY := """
vec3 synth_sky(vec3 d, float t) {
	float e = d.y;
	vec3 top = vec3(0.03, 0.0, 0.1);
	vec3 mid = vec3(0.32, 0.04, 0.42);
	vec3 hor = vec3(1.0, 0.32, 0.55);
	vec3 col = mix(hor, mid, smoothstep(0.0, 0.18, e));
	col = mix(col, top, smoothstep(0.18, 0.7, e));
	// the sun
	vec3 sd = normalize(vec3(0.0, 0.16, -1.0));
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	float sun = smoothstep(0.24, 0.235, ang);
	float sy = (e - (sd.y - 0.24)) / 0.48; // 0 at its bottom, 1 at its top
	float stripes = step(0.5 - (0.5 - sy) * 0.9, fract(sy * 9.0 - t * 0.15));
	sun *= mix(stripes, 1.0, step(0.55, sy));
	vec3 sun_col = mix(vec3(1.0, 0.2, 0.55), vec3(1.0, 0.85, 0.3), clamp(sy, 0.0, 1.0));
	col = mix(col, sun_col * 1.4, sun);
	col += vec3(1.0, 0.35, 0.5) * exp(-ang * 4.0) * 0.35;
	// mountains along the horizon
	float az = atan(d.x, -d.z);
	float h = 0.025 + 0.11 * fbm(vec3(az * 2.2, 3.0, 1.0)) * (0.55 + 0.45 * sin(az * 3.0 + 1.0));
	if (e > -0.02 && e < h) {
		float edge = smoothstep(h - 0.012, h, e);
		col = mix(vec3(0.07, 0.01, 0.14), vec3(1.0, 0.3, 0.85), edge);
	}
	col += vec3(1.0) * stars(d, 110.0, 0.04, t) * smoothstep(0.25, 0.6, e);
	return col;
}
"""

func _build_synthwave():
	_env(Color(0.03, 0.0, 0.08), true)
	_dome(SYNTH_SKY + """
void fragment() {
	ALBEDO = synth_sky(normalize(dir), TIME);
}
""")
	var fl := _floor_node()
	_plane(fl, 176.0, WORLD_HEAD + NOISE + SYNTH_SKY + """
void fragment() {
	vec2 g = wpos.xz + vec2(0.0, TIME * 3.0);
	vec2 cell = abs(fract(g / 3.0) - 0.5);
	float dist = length(wpos.xz);
	float w = 0.02 + dist * 0.0012;
	float line = max(smoothstep(w, 0.0, 0.5 - cell.x), smoothstep(w, 0.0, 0.5 - cell.y));
	vec3 col = vec3(0.025, 0.0, 0.06);
	vec3 neon = mix(vec3(0.1, 0.9, 1.0), vec3(1.0, 0.2, 0.8), smoothstep(-40.0, 40.0, wpos.z));
	col += neon * line * 1.3;
	// the sun on the floor
	col += vec3(1.0, 0.3, 0.5) * exp(-abs(wpos.x) * 0.06) * smoothstep(0.0, -80.0, wpos.z) * 0.25;
	// fades into the horizon
	vec3 far = synth_sky(normalize(vec3(wpos.x, 0.0, wpos.z)), TIME);
	ALBEDO = mix(col, far, smoothstep(30.0, 86.0, dist));
}
""")

# --- Sunset Ocean: warm sky, soft clouds, sparkling waves, a wooden dock -------
const OCEAN_SKY := """
vec3 sun_dir() {
	return normalize(vec3(-0.38, 0.07, -0.92));
}
vec3 ocean_sky(vec3 d, float t) {
	vec3 sd = sun_dir();
	float e = max(d.y, 0.0);
	vec3 col = mix(vec3(1.0, 0.56, 0.36), vec3(0.98, 0.42, 0.42), smoothstep(0.0, 0.12, e));
	col = mix(col, vec3(0.42, 0.33, 0.62), smoothstep(0.1, 0.4, e));
	col = mix(col, vec3(0.13, 0.17, 0.42), smoothstep(0.4, 0.95, e));
	float s = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.75, 0.45) * pow(s, 6.0) * 0.5 + vec3(1.0, 0.9, 0.7) * smoothstep(0.9993, 0.9996, s);
	// a layer of clouds
	vec2 uv = d.xz / (d.y + 0.12);
	float c = fbm(vec3(uv * 1.3 + vec2(t * 0.01, 0.0), 2.0));
	float cl = smoothstep(0.5, 0.8, c) * smoothstep(0.0, 0.08, d.y);
	vec3 cloud_col = mix(vec3(0.55, 0.3, 0.45), vec3(1.0, 0.7, 0.55), pow(s, 2.0));
	col = mix(col, cloud_col, cl * 0.8);
	return col;
}
"""

func _build_ocean():
	_env(Color(0.6, 0.35, 0.4), false)
	_dome(OCEAN_SKY + """
void fragment() {
	ALBEDO = ocean_sky(normalize(dir), TIME);
}
""")
	var fl := _floor_node()
	# the sea, a little under the dock
	_plane(fl, 176.0, WORLD_HEAD + NOISE + OCEAN_SKY + """
void fragment() {
	vec3 cam = CAMERA_MATRIX[3].xyz;
	vec3 v = normalize(wpos - cam);
	vec2 p = wpos.xz * 0.35;
	float t = TIME * 0.6;
	float hx = vnoise(vec3(p.x + 0.1 + t, p.y, t * 0.5)) - vnoise(vec3(p.x - 0.1 + t, p.y, t * 0.5));
	float hz = vnoise(vec3(p.x, p.y + 0.1 - t * 0.7, t)) - vnoise(vec3(p.x, p.y - 0.1 - t * 0.7, t));
	float k = 0.9 * (1.0 - smoothstep(10.0, 70.0, length(wpos.xz)));
	vec3 n = normalize(vec3(-hx * k, 1.0, -hz * k));
	vec3 r = reflect(v, n);
	r.y = abs(r.y);
	float fres = 0.04 + 0.96 * pow(1.0 - max(dot(-v, n), 0.0), 5.0);
	vec3 deep = vec3(0.05, 0.08, 0.2);
	vec3 col = mix(deep, ocean_sky(normalize(r), TIME), clamp(fres, 0.0, 1.0));
	float glit = pow(max(dot(normalize(r), sun_dir()), 0.0), 300.0);
	col += vec3(1.0, 0.85, 0.6) * glit * 2.0;
	ALBEDO = col;
}
""", -1.2, 40)
	# the dock: planks on posts, the end you stand on
	var wood := _mat(WORLD_HEAD + NOISE + """
void fragment() {
	float plank = fract(wpos.z / 0.55);
	float gap = smoothstep(0.0, 0.04, plank) * smoothstep(1.0, 0.96, plank);
	float grain = fbm(vec3(wpos.x * 6.0, wpos.z * 0.6, 0.0));
	vec3 col = mix(vec3(0.3, 0.17, 0.09), vec3(0.5, 0.3, 0.16), grain);
	ALBEDO = col * (0.35 + 0.65 * gap);
}
""")
	var deck := MeshInstance.new()
	var b := CubeMesh.new()
	b.size = Vector3(3.6, 0.2, 14.0)
	deck.mesh = b
	deck.material_override = wood
	deck.transform.origin = Vector3(0, -0.1, 4.6)
	deck.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	fl.add_child(deck)
	for z in [-2.0, 2.4, 6.8, 11.2]:
		for x in [-1.6, 1.6]:
			var post := MeshInstance.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.16
			c.bottom_radius = 0.16
			c.height = 2.4
			c.radial_segments = 8
			post.mesh = c
			post.material_override = wood
			post.transform.origin = Vector3(x, -0.9, z)
			post.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			fl.add_child(post)

# --- Pastel Clouds: a soft sky, a sea of clouds below, floating puffs ---------
const PASTEL_SKY := """
vec3 pastel_sky(vec3 d, float t) {
	float e = d.y;
	vec3 col = mix(vec3(1.0, 0.86, 0.76), vec3(0.99, 0.74, 0.88), smoothstep(-0.05, 0.2, e));
	col = mix(col, vec3(0.66, 0.6, 0.98), smoothstep(0.2, 0.75, e));
	col += vec3(1.0, 0.95, 0.85) * pow(max(dot(d, normalize(vec3(0.5, 0.25, -0.8))), 0.0), 12.0) * 0.4;
	col += vec3(1.0) * stars(d, 70.0, 0.03, t * 2.0) * 0.8 * smoothstep(0.3, 0.7, e);
	return col;
}
"""
const PUFF := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform vec3 tint = vec3(1.0, 0.92, 0.96);
varying vec3 nrm;
void vertex() {
	nrm = (WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec3 n = normalize(nrm);
	float light = 0.72 + 0.28 * clamp(dot(n, normalize(vec3(0.4, 0.8, -0.3))), 0.0, 1.0);
	float under = smoothstep(0.2, -0.6, n.y) * 0.18;
	ALBEDO = tint * light - vec3(0.12, 0.1, 0.0) * under;
}
"""

func _build_clouds():
	_env(Color(0.99, 0.8, 0.88), false)
	_dome(PASTEL_SKY + """
void fragment() {
	ALBEDO = pastel_sky(normalize(dir), TIME);
}
""")
	var fl := _floor_node()
	_platform(fl, 2.6, Color(0.98, 0.9, 0.96), Color(1.0, 0.55, 0.85))
	# puffs round the platform's edge
	var pm := _mat(PUFF)
	for i in range(14):
		var a := TAU * i / 14.0
		var r := 2.7 + 0.25 * sin(i * 2.3)
		var s := MeshInstance.new()
		var sm := SphereMesh.new()
		var size := 0.55 + 0.25 * abs(sin(i * 1.7))
		sm.radius = size
		sm.height = size * 1.6
		sm.radial_segments = 12
		sm.rings = 6
		s.mesh = sm
		s.material_override = pm
		s.transform.origin = Vector3(cos(a) * r, -0.35, sin(a) * r)
		s.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		fl.add_child(s)
	# the cloud sea far below
	_plane(fl, 176.0, WORLD_HEAD + NOISE + PASTEL_SKY + """
void fragment() {
	vec2 p = wpos.xz * 0.06 + vec2(TIME * 0.01, TIME * 0.006);
	float c = fbm(vec3(p, TIME * 0.02));
	vec3 col = mix(vec3(0.93, 0.7, 0.86), vec3(1.0, 0.97, 0.98), smoothstep(0.35, 0.75, c));
	vec3 far = pastel_sky(normalize(vec3(wpos.x, -1.0, wpos.z)), TIME);
	ALBEDO = mix(col, far, smoothstep(25.0, 85.0, length(wpos.xz)));
}
""", -12.0)
	# floating clouds drifting round you
	var ring := Spatial.new()
	ring.name = "Drift"
	add_child(ring)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(11):
		var a := TAU * i / 11.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(22.0, 55.0)
		var cl := Spatial.new()
		cl.transform.origin = Vector3(cos(a) * r, rng.randf_range(-4.0, 14.0), sin(a) * r)
		ring.add_child(cl)
		var tint := Color(1.0, 0.93, 0.97).linear_interpolate(Color(0.95, 0.85, 1.0), rng.randf())
		var mat := _mat(PUFF)
		mat.set_shader_param("tint", Vector3(tint.r, tint.g, tint.b))
		for k in range(5):
			var s := MeshInstance.new()
			var sm := SphereMesh.new()
			var size := rng.randf_range(1.6, 3.2)
			sm.radius = size
			sm.height = size * 1.5
			sm.radial_segments = 12
			sm.rings = 6
			s.mesh = sm
			s.material_override = mat
			s.transform.origin = Vector3((k - 2) * 2.2 + rng.randf_range(-0.5, 0.5), rng.randf_range(-0.6, 0.9), rng.randf_range(-1.0, 1.0))
			s.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			cl.add_child(s)
	_spin.append([ring, 0.012])

# --- Neon City: a rooftop at night among glowing towers and flying lights -----
func _build_city():
	_env(Color(0.01, 0.01, 0.04), true)
	_dome("""
void fragment() {
	vec3 d = normalize(dir);
	float e = d.y;
	vec3 col = mix(vec3(0.3, 0.09, 0.32), vec3(0.06, 0.03, 0.14), smoothstep(-0.05, 0.25, e));
	col = mix(col, vec3(0.008, 0.008, 0.03), smoothstep(0.25, 0.8, e));
	col += vec3(0.9, 0.9, 1.0) * stars(d, 120.0, 0.03, TIME) * smoothstep(0.3, 0.7, e) * 0.7;
	ALBEDO = col;
}
""")
	var fl := _floor_node()
	# the rooftop you stand on, with a glowing edge
	_plane(fl, 9.0, WORLD_HEAD + """
void fragment() {
	vec2 q = abs(wpos.xz);
	float edge = smoothstep(4.1, 4.45, max(q.x, q.y));
	float tiles = step(0.04, fract(wpos.x / 1.5)) * step(0.04, fract(wpos.z / 1.5));
	vec3 col = mix(vec3(0.03, 0.03, 0.05), vec3(0.05, 0.05, 0.08), tiles);
	ALBEDO = col + vec3(0.1, 0.9, 1.0) * edge * (0.8 + 0.2 * sin(TIME * 2.0));
}
""")
	# the towers: one mesh drawn many times
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.custom_data_format = MultiMesh.CUSTOM_DATA_FLOAT
	var box := CubeMesh.new()
	box.size = Vector3(1, 1, 1)
	mm.mesh = box
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var xf := []
	for ring_i in range(3):
		var count: int = [36, 48, 60][ring_i]
		var radius: float = [26.0, 46.0, 70.0][ring_i]
		for i in range(count):
			var a := TAU * i / count + rng.randf_range(-0.05, 0.05)
			var r := radius + rng.randf_range(-5.0, 5.0)
			var w := rng.randf_range(3.0, 7.0)
			var dpt := rng.randf_range(3.0, 7.0)
			var h := rng.randf_range(8.0, 30.0) + ring_i * 8.0
			var base := -24.0 # the street, far below the roof
			var t := Transform(Basis(Vector3.UP, -a) * Basis().scaled(Vector3(w, h, dpt)), Vector3(cos(a) * r, base + h * 0.5, sin(a) * r))
			xf.append([t, rng.randf()])
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i][0])
		mm.set_instance_custom_data(i, Color(xf[i][1], 0, 0, 0))
	var mmi := MultiMeshInstance.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _mat("""
shader_type spatial;
render_mode unshaded, shadows_disabled;
varying vec3 wpos;
varying vec3 wn;
varying float seed;
""" + NOISE + """
void vertex() {
	wpos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
	seed = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec3 col = vec3(0.02, 0.02, 0.05);
	if (abs(wn.y) < 0.5) {
		vec3 side = normalize(vec3(-wn.z, 0.0, wn.x));
		float hcoord = dot(wpos, side);
		vec2 cell = vec2(floor(hcoord / 0.9), floor(wpos.y / 1.2));
		vec2 f = vec2(fract(hcoord / 0.9), fract(wpos.y / 1.2));
		float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75);
		float on = step(0.58, hash13(vec3(cell, seed * 97.0)));
		float pal = hash13(vec3(seed * 13.0, 1.0, 2.0));
		vec3 lit = mix(vec3(1.0, 0.8, 0.45), vec3(0.3, 0.9, 1.0), step(0.5, pal));
		lit = mix(lit, vec3(1.0, 0.35, 0.8), step(0.8, pal));
		col += lit * win * on * 0.9;
	} else {
		col = vec3(0.03, 0.03, 0.06);
	}
	float fog = smoothstep(20.0, 88.0, length(wpos.xz));
	ALBEDO = mix(col, vec3(0.2, 0.07, 0.24), fog * 0.6);
}
""")
	fl.add_child(mmi)
	# flying lights (cars) circling between the towers
	var car_mat := SpatialMaterial.new()
	car_mat.flags_unshaded = true
	var car_mesh := CubeMesh.new()
	car_mesh.size = Vector3(0.5, 0.25, 1.2)
	for i in range(14):
		var n := MeshInstance.new()
		n.mesh = car_mesh
		var m := car_mat.duplicate()
		m.albedo_color = [Color(1.0, 0.3, 0.75), Color(0.3, 0.95, 1.0), Color(1.0, 0.85, 0.4)][i % 3]
		n.material_override = m
		n.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		fl.add_child(n)
		var speed := (0.06 + 0.04 * (i % 4)) * (1.0 if i % 2 == 0 else -1.0)
		_cars.append([n, 14.0 + i * 3.3, 1.5 + (i % 5) * 2.4, speed, i * 1.3])
