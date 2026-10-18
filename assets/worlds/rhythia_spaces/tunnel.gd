extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Tunnel" (Tunnel.cs + tunnel.tscn): 14 alternating ring quads
# (8x8, scaled 3.5, every 7.5 units) flying toward you at approach rate / 2,
# over a long neon road, all tinted by the hit colour, in black depth fog.

const RING_LOOP_END := 52.5
const FOG := [Color(0, 0, 0), 5.0, 150.0, 0.8485127]
var rings: Spatial
var mat_road: ShaderMaterial
var mat_a: ShaderMaterial
var mat_b: ShaderMaterial

func _build():
	env.background_color = Color(0, 0, 0)
	var dir := "res://assets/worlds/rhythia_spaces/tunnel/"
	mat_a = surface_material(load(dir + "tunnel_ring_b.png"), {"color": note_hit_color, "use_alpha": true, "fade": [10.0, 40.0], "fog": FOG})
	mat_b = surface_material(load(dir + "tunnel_space_a.png"), {"color": note_hit_color, "use_alpha": true, "fade": [10.0, 40.0], "fog": FOG})
	mat_road = surface_material(load(dir + "tunnel_neonroad.png"), {"color": note_hit_color, "use_alpha": true, "fade": [150.0, 10.0], "fog": FOG})
	rings = Spatial.new()
	rings.scale = Vector3(3.5, 3.5, 3.5)
	add_child(rings)
	var q := QuadMesh.new()
	q.size = Vector2(8, 8)
	for k in range(-6, 8):
		# z = 7.5 * -k: even steps use ring A, odd steps ring B (as in the scene)
		var m = mat_a if k % 2 == 0 else mat_b
		mesh_node(q, m, Transform(Basis(), Vector3(0, 0, -7.5 * k)), rings)
	var road := PlaneMesh.new()
	road.size = Vector2(120, 120)
	mesh_node(road, mat_road, Transform(Basis().scaled(Vector3(0.2, 1.204, 2.806)), Vector3(0, -20, 0)))

func _tick(_delta):
	if space_effects:
		rings.translation.z = fmod(OS.get_ticks_msec() / 1000.0 * approach_rate / 2.0, RING_LOOP_END)
	mat_a.set_shader_param("albedo", note_hit_color)
	mat_b.set_shader_param("albedo", note_hit_color)
	mat_road.set_shader_param("albedo", note_hit_color)
