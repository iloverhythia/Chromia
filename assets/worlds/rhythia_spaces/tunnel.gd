extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Tunnel": square neon rings (alternating full frames and corner
# brackets) rushing toward the player at approach-rate speed over a tiled road.

const RING_LOOP_END := 52.5
const RING_SPACING := 7.5
const RING_COUNT := 14
const TILE := 2.0
var rings: Spatial
var road: MeshInstance
var tile_mat: SpatialMaterial
var ring_mat_a: SpatialMaterial
var ring_mat_b: SpatialMaterial

func _build():
	env.background_color = Color(0.01, 0.01, 0.015)
	var tex_a = shape_texture(256, 0, 0.02, 0.025)
	var tex_b = shape_texture(256, 3, 0.035, 0.03)
	ring_mat_a = make_unshaded(note_hit_color, tex_a, true, 80.0)
	ring_mat_b = make_unshaded(note_hit_color, tex_b, true, 80.0)
	rings = Spatial.new()
	rings.name = "Rings"
	add_child(rings)
	for i in range(RING_COUNT):
		var m = ring_mat_a if i % 2 == 0 else ring_mat_b
		add_quad(rings, Vector2(11, 11), m, Vector3(0, 0.5, 5.0 - RING_SPACING * (i + 1)))

	tile_mat = make_unshaded(note_hit_color, tile_texture(128, 0.05, 0.04, 0.2), true, 80.0)
	tile_mat.uv1_scale = Vector3(4.0, 60.0, 1.0)
	var pm := PlaneMesh.new()
	pm.size = Vector2(TILE * 4.0, TILE * 60.0)
	road = MeshInstance.new()
	road.name = "Road"
	road.mesh = pm
	road.material_override = tile_mat
	road.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	road.translation = Vector3(0, -5.0, -55.0)
	add_child(road)

func _tick(_delta):
	if space_effects:
		var p = fmod(time * approach_rate / 2.0, RING_LOOP_END)
		rings.translation.z = p
		road.translation.z = -55.0 + fmod(p, TILE)
	tile_mat.albedo_color = Color(note_hit_color.r, note_hit_color.g, note_hit_color.b, 0.6)
	ring_mat_a.albedo_color = note_hit_color
	ring_mat_b.albedo_color = note_hit_color
