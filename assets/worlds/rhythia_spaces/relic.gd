extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Relic": an ancient golden crystal floating in a dark temple between
# two stone pillars, wrapped in rotating halos. Particle "Aura" swirls around
# the relic and embers rise from the "Left" and "Right" pillars.

const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform vec4 base : hint_color = vec4(0.12, 0.06, 0.01, 1.0);
uniform vec4 rim : hint_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float power = 2.0;
uniform float bands = 0.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	float facet = 0.5 + 0.5 * dot(NORMAL, normalize(vec3(0.3, 0.8, 0.5)));
	vec3 c = base.rgb * (0.4 + facet) + rim.rgb * f;
	ALBEDO = c;
}
"""
const GOLD := Color(1.0, 0.72, 0.28)
var relic: MeshInstance
var halo_a: MeshInstance
var halo_b: MeshInstance
var particles: Spatial
var aura: CPUParticles
var left: CPUParticles
var right: CPUParticles
var relic_y := 1.0
var halo_mat: SpatialMaterial

func _build():
	env.background_color = Color(0.012, 0.007, 0.004)
	var sh := Shader.new()
	sh.code = RIM_SHADER

	# backdrop glow
	add_quad(self, Vector2(40, 40), make_unshaded(Color(0.5, 0.28, 0.08, 0.5), dot_texture(64, 0.0), true), Vector3(0, relic_y, -70))

	# relic (octahedral crystal)
	var crystal := SphereMesh.new()
	crystal.radius = 2.2
	crystal.height = 7.0
	crystal.radial_segments = 4
	crystal.rings = 1
	var rm := ShaderMaterial.new()
	rm.shader = sh
	rm.set_shader_param("base", Color(0.35, 0.2, 0.05))
	rm.set_shader_param("rim", Color(1.0, 0.85, 0.45))
	relic = MeshInstance.new()
	relic.name = "Relic"
	relic.mesh = crystal
	relic.material_override = rm
	relic.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	relic.translation = Vector3(0, relic_y, -40)
	add_child(relic)

	# halos
	halo_mat = make_unshaded(GOLD, shape_texture(256, 1, 0.025, 0.05), true, 0.0)
	halo_a = add_quad(self, Vector2(11, 11), halo_mat, relic.translation)
	halo_b = add_quad(self, Vector2(14, 14), halo_mat, relic.translation)

	# pillars + floor
	var pm := ShaderMaterial.new()
	pm.shader = sh
	pm.set_shader_param("base", Color(0.06, 0.045, 0.035))
	pm.set_shader_param("rim", Color(0.45, 0.28, 0.1))
	pm.set_shader_param("power", 3.0)
	for side in [-1, 1]:
		for k in range(3):
			var cube := CubeMesh.new()
			cube.size = Vector3(2.4, 14, 2.4)
			var mi := MeshInstance.new()
			mi.mesh = cube
			mi.material_override = pm
			mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			mi.translation = Vector3(side * (11 + k * 2), 0.5, -28 - k * 14)
			add_child(mi)
	var floor_mat := make_unshaded(Color(1.0, 0.6, 0.2, 0.18), tile_texture(64, 0.04, 0.0, 0.1), true, 70.0)
	floor_mat.uv1_scale = Vector3(16, 16, 1)
	var fp := PlaneMesh.new()
	fp.size = Vector2(64, 64)
	var fl := MeshInstance.new()
	fl.mesh = fp
	fl.material_override = floor_mat
	fl.translation = Vector3(0, -6.5, -35)
	add_child(fl)

	# particles
	particles = Spatial.new()
	particles.name = "Particles"
	add_child(particles)
	var dot = dot_texture(32, 0.15)
	aura = _particles("Aura", dot, 70, 3.0, relic.translation)
	aura.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	aura.emission_sphere_radius = 3.5
	aura.direction = Vector3(0, 1, 0)
	aura.spread = 180.0
	aura.initial_velocity = 1.2
	aura.orbit_velocity = 0.0
	aura.radial_accel = 0.8
	aura.scale_amount = 0.35
	left = _particles("Left", dot, 40, 3.5, Vector3(-11, 7.7, -28))
	right = _particles("Right", dot, 40, 3.5, Vector3(11, 7.7, -28))
	for p in [left, right]:
		p.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(1.0, 0.2, 1.0)
		p.direction = Vector3(0, 1, 0)
		p.spread = 15.0
		p.initial_velocity = 2.5
		p.initial_velocity_random = 0.5
		p.gravity = Vector3(0, 0.5, 0)
		p.scale_amount = 0.5
		p.scale_amount_random = 0.6

func _particles(nm: String, tex: Texture, amount: int, life: float, pos: Vector3) -> CPUParticles:
	var mat := make_unshaded(Color(1, 1, 1), tex, true)
	mat.vertex_color_use_as_albedo = true
	mat.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = mat
	var p := CPUParticles.new()
	p.name = nm
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.translation = pos
	p.gravity = Vector3()
	p.color = GOLD
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 0.4, 0.1, 0))
	g.add_point(0.15, Color(1, 0.95, 0.7, 1))
	p.color_ramp = g
	particles.add_child(p)
	return p

func _tick(delta):
	aura.emitting = space_effects
	left.emitting = space_effects
	right.emitting = space_effects
	relic.rotate_y(delta * 0.5)
	relic.translation.y = relic_y + sin(time * 1.2) * 0.4
	halo_a.rotation = Vector3(time * 0.4, time * 0.7, 0.0)
	halo_b.rotation = Vector3(-time * 0.3, 0.6, time * 0.5)
	halo_mat.albedo_color = GOLD.linear_interpolate(note_hit_color, 0.3)
