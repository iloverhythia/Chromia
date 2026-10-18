extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Squircles" (Squircles.cs + squircles.tscn): two layers of glowing
# squircles (squircle_bloom.png) drifting and spinning slowly in front of a dark
# backdrop. While playing, the backdrop is the note hit colour darkened by 90%
# and the squircles take the hit colour lightened by 10%.
# CPUParticles settings mirror the original CPUParticles3D nodes (local coords,
# flattened onto a plane facing the camera, rotate around local Y).

# Godot 4 multiplies the colour background by background_energy_multiplier
# (1.2, in linear space); Godot 3 ignores bg energy for colour backgrounds,
# so it is folded into the colour (1.2 ^ (1 / 2.2)).
const BG_ENERGY := 1.086

var near: CPUParticles
var far: CPUParticles

func _build():
	near = $ParticlesNear
	far = $ParticlesFar
	_update_color(note_hit_color)

func _update_color(c: Color):
	var d := c.darkened(0.9)
	env.background_color = Color(d.r * BG_ENERGY, d.g * BG_ENERGY, d.b * BG_ENERGY)
	var p := c.lightened(0.1)
	near.color = p
	far.color = p

func _tick(_delta):
	_update_color(note_hit_color)
