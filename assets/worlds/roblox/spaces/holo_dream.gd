extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Holo Dream" (HoloDream): the two sets of shapes swap
# colours on every hit: one takes the new note colour, the other the previous one.

var c1 = Color8(255, 102, 204)
var c2 = Color8(4, 175, 236)

func _init():
	slug = "holo_dream"

func space_hit(col):
	c2 = c1
	c1 = col
	tween(group_obj("c1"), {"Color": c1}, 0.275)
	tween(group_obj("c2"), {"Color": c2}, 0.275)
