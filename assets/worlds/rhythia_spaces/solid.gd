extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Solid" (Solid.cs + solid.tscn): just a background colour, the hit
# colour darkened by 90% (background energy 1.2).

func _build():
	env.background_energy = 1.2
	_tick(0)

func _tick(_delta):
	var c := note_hit_color.darkened(0.9)
	if env.background_color != c:
		env.background_color = c
