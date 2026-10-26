extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Christmas" (ChristmasDecorScript): on every hit three
# random street lamps flash in the note colour and fade back to warm yellow; the
# fairy lights switch to one colour (red / green / blue / yellow) on each beat.

const LIGHTS = {
	"R": [Color8(255, 0, 0), Color(76.5 / 255, 0, 0)],
	"G": [Color8(0, 255, 0), Color(0, 76.5 / 255, 0)],
	"B": [Color8(9, 137, 207), Color(2.7 / 255, 41.1 / 255, 62.1 / 255)],
	"Y": [Color8(255, 176, 0), Color(76.5 / 255, 52.8 / 255, 0)],
}
var lamps = []

func _init():
	slug = "christmas"

func space_init():
	var lf = space_obj.child("LightFixes")
	if lf != null:
		for v in lf.kids():
			var sl = v.child("SurfaceLight")
			if sl != null:
				sl.set_enabled(true)
	var l = space_obj.child("Lamps")
	lamps = l.kids() if l != null else []

func space_hit(col):
	var idx = []
	for i in range(lamps.size()):
		idx.append(i)
	for _k in range(3):
		if idx.empty():
			break
		var j: int = idx[rand_int(0, idx.size() - 1)]
		idx.erase(j)
		_flicker(lamps[j], col)

func space_beat():
	var on: String = ["R", "G", "B", "Y"][rand_int(0, 3)]
	for k in LIGHTS.keys():
		group_color(k, LIGHTS[k][0] if k == on else LIGHTS[k][1])

func _flicker(lamp, col: Color):
	var light = lamp.child("Light")
	if light == null:
		return
	light.set_color(col)
	tween(light, {"Color": Color8(255, 176, 0)}, 0.45, "Cubic", "In")
	var pl = light.child("PointLight")
	if pl != null:
		pl.set_color(col)
		tween(pl, {"Color": Color8(255, 246, 119)}, 0.45, "Cubic", "In")
