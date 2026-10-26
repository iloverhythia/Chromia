extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Beyond Reality" (BeyondRealityScript): a glowing ring
# hovers and turns over the water; on every hit a random crystal lights up in
# the note colour; the drifting specks take the current colour.

var crystals = [] # [force field part, [decals]]
var circle
var specks
var t = 0.0

func _init():
	slug = "beyond_reality"

func space_init():
	var c = space_obj.at("Dynamic/Crystals")
	if c != null:
		for v in c.kids():
			var ff = v.child("FF")
			var decals = []
			var spr = v.child("Sprites")
			if spr != null:
				for s in spr.kids():
					s.set_transparency(1)
					var d = s.child("Decal")
					if d != null:
						decals.append(d)
			if ff != null:
				ff.set_transparency(1)
			crystals.append([ff, decals])
	circle = space_obj.at("Dynamic/Circle")
	specks = space_obj.at("Dynamic/Specks/ParticleEmitter")

func space_load():
	add_water(cf(Vector3(0, -14, 0)), Vector3(480, 4, 480))

func space_update(dt):
	t += dt
	if circle != null:
		var p: Transform = circle.get_pivot()
		var k = (sin(deg2rad(fmod(t * 90, 360))) + 1) / 2
		var r: Transform = rot_only(p) * cfa(-dt * PI / 8, 0, 0)
		r.origin = Vector3(p.origin.x, k + 3, p.origin.z)
		circle.pivot_to(r)
	if specks != null and specks.extra.get("last_col") != get_color():
		specks.extra["last_col"] = get_color()
		specks.set_emitter_color(get_color())

func space_hit(col):
	if crystals.empty():
		return
	var c = crystals[rand_int(0, crystals.size() - 1)]
	for d in c[1]:
		d.set_transparency(0)
		d.set_color(col)
		tween(d, {"Transparency": 1.0}, 0.35, "Sine", "In")
	if c[0] != null:
		c[0].set_transparency(0)
		c[0].set_color(col)
		tween(c[0], {"Transparency": 1.0}, 0.35, "Sine", "In")
