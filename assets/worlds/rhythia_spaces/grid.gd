extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Grid" (Grid.cs + grid.tscn): two 120x120 tiled planes, a floor at
# y = -10 and a ceiling at y = 10, tinted by the hit colour, with the tiles
# scrolling toward you (UV offset +3/s) through dark purple depth fog.

const FOG := Color(0.0470588, 0.0313726, 0.109804)
var mat: ShaderMaterial
var uv_off := 0.0

func _build():
	# Godot 4 fogs the background too, so the sky ends up the fog colour.
	env.background_color = FOG
	# (the fog starts at 0, not 10: the floor and ceiling are 10 away, so the
	# patch straight above and below you had no fog at all and, with the steep
	# fog curve, showed as a sharp bright circle in the hit colour)
	mat = surface_material(load("res://assets/worlds/rhythia_spaces/grid/grid_tile.png"), {
		"color": note_hit_color, "uv_scale": Vector2(34, 34),
		"fog": [FOG, 0.0, 60.0, 0.15],
	})
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	mesh_node(pm, mat, Transform(Vector3(-1, 0, 8.74228e-08), Vector3(0, 1, 0), Vector3(-8.74228e-08, 0, -1), Vector3(0, -10, 0)))
	mesh_node(pm, mat, Transform(Vector3(1, 0, 0), Vector3(0, -1, -8.74228e-08), Vector3(0, 8.74228e-08, -1), Vector3(0, 10, 0)))

func _tick(delta):
	mat.set_shader_param("albedo", note_hit_color)
	uv_off = fmod(uv_off + delta * 3.0, 1.0)
	mat.set_shader_param("uv_offset", Vector2(0, uv_off))
