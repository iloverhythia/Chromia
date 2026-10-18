extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Galaxy" (Galaxy.cs + galaxy.tscn): panorama starfield sky that
# slowly rotates, and a huge transparent road whose rainbow edge strips scroll
# toward the player. The original's depth fog only touches the sky
# (fog_sky_affect 0.25 toward black; the road has disable_fog), reproduced here
# with background_energy 0.75. The original's planet/moon node is hidden, so it
# is left out.

var tile_mat: SpatialMaterial

func _build():
	# the base class forces BG_COLOR; this space uses the panorama sky
	env.background_mode = Environment.BG_SKY
	tile_mat = ($Road.mesh as PlaneMesh).material

func _tick(delta):
	# sky rotation: SkyRotation += (Down + Right) * delta / 100
	env.background_sky_rotation += Vector3(1.0, -1.0, 0.0) * (delta / 100.0)
	# tile movement: Uv1Offset += Up * delta / 2
	tile_mat.uv1_offset.y = fmod(tile_mat.uv1_offset.y + delta * 0.5, 1.0)
