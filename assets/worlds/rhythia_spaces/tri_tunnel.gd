extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Tri Tunnel" (TriTunnel.cs + tritunnel.tscn): the triangular tunnel
# mesh at 25% opacity, tinted by the hit colour, sliding toward you at
# approach rate / 6 and jumping back once it has moved 148 units.

const LOOP_END := 148.0
var tunnel: MeshInstance
var mat: ShaderMaterial

func _build():
	env.background_color = Color(0, 0, 0)
	mat = surface_material(null, {
		"color": note_hit_color, "opacity": 0.25, "fade": [65.0, 10.0], "cull_back": true,
	})
	var mesh = load("res://assets/worlds/rhythia_spaces/tri_tunnel/tunnel.obj")
	tunnel = mesh_node(mesh, mat, Transform(Vector3(-8.742278e-09, 0, 0.2), Vector3(0, 0.2, 0), Vector3(-0.2, 0, -8.742278e-09), Vector3.ZERO))

func _tick(delta):
	if tunnel.translation.z < LOOP_END and space_effects:
		tunnel.translation.z += approach_rate * delta / 6.0
	else:
		tunnel.translation.z = 0.0
	mat.set_shader_param("albedo", note_hit_color if space_effects else Color(1, 1, 1))
