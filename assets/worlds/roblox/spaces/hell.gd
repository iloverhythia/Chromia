extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Hell" (HellSpace): a fiery pit with hanging chains that
# keep turning, every other one the opposite way.

var chains = []

func _init():
	slug = "hell"

func space_init():
	var c = space_obj.child("Chains")
	chains = c.kids() if c != null else []
	chains.sort_custom(self, "_by_name")

func _by_name(a, b):
	return a.rname < b.rname

func space_update(dt):
	var step = rate_limit("hell", 120, dt)
	if step <= 0:
		return
	var i = 0
	for m in chains:
		var d = -step if i % 2 == 0 else step
		m.pivot_to(m.get_pivot() * cfa(deg2rad(d * 20), 0, 0))
		i += 1
