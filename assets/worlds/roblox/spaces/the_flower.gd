extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "The Flower" (TheFlowerSpace): a spiky neon flower that
# slowly turns in front of you over a scrolling floor; the neon takes a darker
# shade of the note colour on every hit.

var bottom
var flower

func _init():
	slug = "the_flower"

func space_init():
	bottom = space_obj.at("Dynamic/Bottom")
	flower = space_obj.at("Dynamic/Flower")
	group_color("neon", Color(1, 1, 1).linear_interpolate(Color(0, 0, 0), 0.35))

func space_update(dt):
	if bottom != null:
		var b: Transform = bottom.get_pivot()
		b.origin.x = rmod(b.origin.x + dt * 100, 2048)
		bottom.pivot_to(b)
	if flower != null:
		var spin = 360.0 if Rhythia.get("vr") else 10.0
		flower.pivot_to(flower.get_pivot() * cfa(deg2rad(dt * spin), 0, 0))

func space_hit(col):
	tween(group_obj("neon"), {"Color": col.linear_interpolate(Color(0, 0, 0), 0.35)}, 0.15)
