extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Circular Tunnel" (CircularTunnel.cs + circulartunnel.tscn): 14 ring
# quads (8x8, scaled 3.5, every 7.5 units) flying toward you at approach
# rate / 2, tinted by the hit colour, in black depth fog.

const RING_LOOP_END := 52.5
var rings: Spatial
var mat: ShaderMaterial

func _build():
	env.background_color = Color(0, 0, 0)
	mat = surface_material(load("res://assets/worlds/rhythia_spaces/circular_tunnel/ring.png"), {
		"color": note_hit_color, "use_alpha": true, "fade": [15.0, 40.0],
		"fog": [Color(0, 0, 0), 5.0, 150.0, 0.8485127],
	})
	rings = Spatial.new()
	rings.scale = Vector3(3.5, 3.5, 3.5)
	add_child(rings)
	var q := QuadMesh.new()
	q.size = Vector2(8, 8)
	for k in range(-6, 8):
		mesh_node(q, mat, Transform(Basis(), Vector3(0, 0, -7.5 * k)), rings)

func _tick(_delta):
	if space_effects:
		rings.translation.z = fmod(OS.get_ticks_msec() / 1000.0 * approach_rate / 2.0, RING_LOOP_END)
	mat.set_shader_param("albedo", note_hit_color)
