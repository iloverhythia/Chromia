extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Squircles": a dark backdrop tinted by the last hit colour, with
# squircle outlines drifting and spinning toward the player in two layers.

var near: CPUParticles
var far: CPUParticles

func _build():
	var start = cover_average(note_hit_color)
	note_hit_color = start
	last_hit_color = start
	var tex = shape_texture(128, 2, 0.08, 0.06)
	near = _make_particles("ParticlesNear", tex, 18, 14.0, Vector3(0, 0, -42), Vector3(14, 8, 2), 3.0, 0.9, 1.6)
	far = _make_particles("ParticlesFar", tex, 40, 20.0, Vector3(0, 0, -80), Vector3(40, 24, 4), 2.0, 1.2, 2.4)
	_update_color(start)

func _make_particles(nm: String, tex: Texture, amount: int, life: float, pos: Vector3, extents: Vector3, speed: float, smin: float, smax: float) -> CPUParticles:
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_transparent = true
	mat.vertex_color_use_as_albedo = true
	mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	mat.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	mat.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = mat
	var p := CPUParticles.new()
	p.name = nm
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.translation = pos
	p.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0, 0, 1)
	p.spread = 8.0
	p.gravity = Vector3()
	p.initial_velocity = speed
	p.initial_velocity_random = 0.4
	p.angular_velocity = 25.0
	p.angular_velocity_random = 1.0
	p.angle = 180.0
	p.angle_random = 1.0
	p.scale_amount = smax
	p.scale_amount_random = 1.0 - smin / smax
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 1))
	p.color_ramp = g
	add_child(p)
	return p

func _update_color(c: Color):
	env.background_color = c.darkened(0.9)
	near.color = c.lightened(0.1)
	far.color = Color(near.color.r, near.color.g, near.color.b, 0.6)

func _tick(_delta):
	_update_color(note_hit_color)
