extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Circular Tunnel": glowing circular rings rushing toward the player
# at approach-rate speed, tinted by the last hit note colour.

const RING_LOOP_END := 52.5
const RING_SPACING := 7.5
const RING_COUNT := 14
var rings: Spatial
var ring_mat: SpatialMaterial

func _build():
	env.background_color = Color(0.008, 0.008, 0.014)
	ring_mat = make_unshaded(note_hit_color, shape_texture(256, 1, 0.018, 0.03), true, 90.0)
	rings = Spatial.new()
	rings.name = "Rings"
	add_child(rings)
	for i in range(RING_COUNT):
		var mi = add_quad(rings, Vector2(12, 12), ring_mat, Vector3(0, 0, 5.0 - RING_SPACING * (i + 1)))
		
func _tick(_delta):
	if space_effects:
		rings.translation.z = fmod(time * approach_rate / 2.0, RING_LOOP_END)
	ring_mat.albedo_color = note_hit_color
