extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Cosmic Pyramid" (CosmicPyramid): a glowing pyramid with a
# turning ring of light; its sprites take the note colour on every hit.

var spin

func _init():
	slug = "cosmic_pyramid"

func space_init():
	spin = space_obj.at("Dynamic/SpinPart")

func space_update(dt):
	if spin == null or rate_limit("pyramid", 60, dt) <= 0:
		return
	var deg = 360.0 if Rhythia.get("vr") else 20.0
	spin.pivot_to(spin.get_pivot() * cfa(deg2rad(dt * deg), 0, 0))

func space_hit(col):
	tween(group_obj("dec"), {"Color": col}, 0.1)
