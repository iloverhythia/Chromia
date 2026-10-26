extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "World Cracks" (WorldCracksSpace): on every hit one of the
# cracks splits open and glows in the note colour, then closes again.

var cracks = [] # [cover part, group name, glow decal]

func _init():
	slug = "world_cracks"

func space_init():
	var cr = space_obj.child("Cracks")
	if cr == null:
		return
	for c in cr.kids():
		var neons = space_obj.at("Static/" + c.rname + "/Neons")
		var decal = space_obj.at("Static/" + c.rname + "/Neons/BackSprite/Decal")
		var g: String = c.rname
		if neons == null or not groups.has(g):
			continue
		var c0: Color = groups[g].c0
		group_color(g, c0)
		if decal != null:
			decal.set_color(c0)
		c.set_transparency(0)
		cracks.append([c, g, decal])

func space_hit(col):
	if cracks.size() < 2:
		return
	var i = rand_int(1, cracks.size() - 1)
	var tmp = cracks[i]
	cracks[i] = cracks[0]
	cracks[0] = tmp
	var c = cracks[0]
	if env_effects:
		group_color(c[1], col)
	if c[2] != null:
		c[2].set_color(col)
	c[0].set_transparency(1)
	tween(c[0], {"Transparency": 0.0}, 0.55, "Sine", "In")
