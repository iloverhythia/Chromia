extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Waves" (Waves.cs + waves.tscn), ported to Godot 3.
# - Sky: Rhythia's sky_noise_waves sky shader, drawn on a far-plane sphere
#   (Godot 3 has no sky shaders). Noise contour lines in red, or tinted with the
#   map cover's colours; the cover is hidden when SpaceEffects is off.
# - Water: 4000x4000 plane at y = -2.01 with the water_ripple shader (dark,
#   fresnel reflection of the screen with noise ripples) and the "echo" ring
#   that expands over the first 12 seconds (tween 0 -> 0.5 in 12 s).
# The original's CPUParticles3D node is hidden (visible = false), so it is not
# recreated; the menu-only intro (camera tilt / coverage fade) does not apply
# in gameplay.

var water_mat: ShaderMaterial
var echo_done := false

func _build():
	var sky_mat: ShaderMaterial = $Sky.mesh.material
	water_mat = $Water.mesh.material
	# Gameplay state of Waves.UpdateState(true): image = map cover, or the
	# empty texture when SpaceEffects is disabled.
	if space_effects and cover != null:
		sky_mat.set_shader_param("image_a", cover)
		sky_mat.set_shader_param("has_image_a", 1.0)
		sky_mat.set_shader_param("image_lerp", 1.0)
	else:
		sky_mat.set_shader_param("has_image_a", 0.0)
		sky_mat.set_shader_param("image_lerp", 0.0)
	water_mat.set_shader_param("echo", 0.0)

func _tick(_delta):
	if echo_done:
		return
	var e = time / 24.0
	if e >= 0.5:
		e = 0.5
		echo_done = true
	water_mat.set_shader_param("echo", e)
