extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Arcade" (ArcadeSpace): the middle sprites take the note
# colour on every hit, and the side sprites take the colour before it.

var last = Color8(234, 0, 255)

func _init():
	slug = "arcade"

func space_hit(col):
	tween(group_obj("mid"), {"Color": col}, 0.5)
	tween(group_obj("side"), {"Color": last}, 0.5)
	last = col
