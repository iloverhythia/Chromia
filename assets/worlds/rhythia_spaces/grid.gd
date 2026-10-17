extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Grid": a glowing grid ceiling (and a fainter floor) scrolling
# toward the player, tinted by the last hit note colour.

const TILE := 2.0
const SPEED := 6.0 # Uv1Offset += 3/s on a 2-unit tile
var top: MeshInstance
var bottom: MeshInstance
var mat_top: SpatialMaterial
var mat_bottom: SpatialMaterial

func _build():
	env.background_color = Color(0.006, 0.006, 0.012)
	var tex = tile_texture(128, 0.035, 0.0, 0.12)
	mat_top = make_unshaded(note_hit_color, tex, true, 70.0)
	mat_top.uv1_scale = Vector3(60.0, 60.0, 1.0)
	mat_bottom = mat_top.duplicate()
	top = _plane(mat_top, 5.0)
	bottom = _plane(mat_bottom, -5.0)

func _plane(mat: SpatialMaterial, y: float) -> MeshInstance:
	var pm := PlaneMesh.new()
	pm.size = Vector2(TILE * 60.0, TILE * 60.0)
	var mi := MeshInstance.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.translation = Vector3(0, y, -50)
	add_child(mi)
	return mi

func _tick(_delta):
	var off = fmod(time * SPEED, TILE) if space_effects else 0.0
	top.translation.z = -50.0 + off
	bottom.translation.z = -50.0 + off
	mat_top.albedo_color = note_hit_color
	mat_bottom.albedo_color = Color(note_hit_color.r, note_hit_color.g, note_hit_color.b, 0.35)
