extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Rift" (RiftScript): a city torn open by a rift; the big
# neon triangle and the sprites take the note colour on every hit.

func _init():
	slug = "rift"

func space_init():
	_set_color(Color8(0, 255, 255), false)

func space_hit(col):
	_set_color(col, true)

func _set_color(c: Color, anim: bool):
	var neon = space_obj.at("Colored/Neon")
	if anim:
		tween(group_obj("spr"), {"Color": c}, 0.275)
		if neon != null:
			tween(neon, {"Color": c}, 0.275)
	else:
		group_color("spr", c)
		if neon != null:
			neon.set_color(c)
