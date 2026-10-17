extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Solid": a flat background colour that follows the last hit note
# colour (darkened 90%). Starts from the average colour of the map cover.

func _build():
	var start = cover_average(note_hit_color)
	note_hit_color = start
	last_hit_color = start
	env.background_color = start.darkened(0.9)

func _tick(_delta):
	env.background_color = note_hit_color.darkened(0.9)
