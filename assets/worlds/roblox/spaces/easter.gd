extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Easter" (EasterScript): the island lagoon, and a random
# easter egg flashes in the note colour on every hit.

var eggs = []

func _init():
	slug = "easter"

func space_init():
	var e = space_obj.child("Eggs")
	eggs = e.kids() if e != null else []

func space_load():
	for v in eggs:
		if v.is_part():
			v.set_color(Color(1, 1, 1))
	var w = space_obj.child("WaterTerrainPart")
	if w != null:
		w.visible = false
		add_water(w.get_cframe(), w.size, {"WaterColor": Color8(0, 173, 138), "WaterTransparency": 0.6, "WaterWaveSize": 0.45, "WaterWaveSpeed": 15})

func space_hit(col):
	if eggs.empty():
		return
	var v = eggs[rand_int(0, eggs.size() - 1)]
	v.set_color(col)
	tween(v, {"Color": Color(1, 1, 1)}, 0.3)
