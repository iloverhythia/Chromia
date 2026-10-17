extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Galaxy": a slowly rotating starfield/nebula sky with a glassy
# tiled road gliding underneath.

const TILE := 2.0
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;
uniform sampler2D noise;
uniform vec4 col_a : hint_color = vec4(0.35, 0.12, 0.55, 1.0);
uniform vec4 col_b : hint_color = vec4(0.10, 0.45, 0.80, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float n = texture(noise, uv * vec2(2.0, 1.0)).r;
	float n2 = texture(noise, uv * vec2(5.0, 2.5) + vec2(0.37, 0.11)).r;
	float band = exp(-pow((uv.y - 0.5 + 0.12 * sin(uv.x * 6.2832)) * 5.0, 2.0));
	float neb = smoothstep(0.45, 0.95, n * 0.75 + n2 * 0.25) * (0.25 + band);
	vec3 c = vec3(0.004, 0.002, 0.015);
	c += col_a.rgb * neb * 0.35;
	c += col_b.rgb * pow(neb, 2.5) * 0.5;
	c += vec3(0.025, 0.02, 0.04) * band;
	vec2 g = uv * vec2(700.0, 350.0);
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id);
	vec2 o = vec2(hash(id + 1.3), hash(id + 2.1)) - 0.5;
	float s = step(0.982, h) * smoothstep(0.32, 0.0, length(f - o * 0.4));
	s *= 0.4 + 0.6 * (h - 0.982) / 0.018;
	s *= 0.75 + 0.25 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
	ALBEDO = c + vec3(s) * mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.9, 0.8), o.x + 0.5);
}
"""
var sky: MeshInstance
var road: MeshInstance
var tile_mat: SpatialMaterial
var road_off := 0.0

func _build():
	env.background_color = Color(0, 0, 0)
	var noise := OpenSimplexNoise.new()
	noise.seed = 7
	noise.octaves = 4
	noise.period = 64.0
	noise.persistence = 0.55
	var nt := NoiseTexture.new()
	nt.width = 512
	nt.height = 256
	nt.seamless = true
	nt.noise = noise
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_param("noise", nt)
	var sphere := SphereMesh.new()
	sphere.radius = 300.0
	sphere.height = 600.0
	sphere.radial_segments = 32
	sphere.rings = 16
	sky = MeshInstance.new()
	sky.name = "Sky"
	sky.mesh = sphere
	sky.material_override = sm
	sky.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	sky.rotation = Vector3(0.3, 0.0, 0.2)
	add_child(sky)

	tile_mat = make_unshaded(Color(0.55, 0.65, 1.0, 0.55), tile_texture(128, 0.06, 0.08, 0.3), true, 70.0)
	tile_mat.uv1_scale = Vector3(3.0, 50.0, 1.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(TILE * 3.0, TILE * 50.0)
	road = MeshInstance.new()
	road.name = "Road"
	road.mesh = pm
	road.material_override = tile_mat
	road.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	road.translation = Vector3(0, -4.0, -45.0)
	add_child(road)

func _tick(delta):
	# sky rotation: (Down + Right) * delta / 100
	sky.rotation += Vector3(1.0, -1.0, 0.0) * delta / 100.0
	# tile movement: Uv1Offset += Up * delta / 2  (half a tile per second)
	road_off = fmod(road_off + delta * TILE / 2.0, TILE)
	road.translation.z = -45.0 + road_off
	tile_mat.albedo_color = Color(0.55, 0.65, 1.0, 0.55).linear_interpolate(Color(note_hit_color.r, note_hit_color.g, note_hit_color.b, 0.55), 0.35)
