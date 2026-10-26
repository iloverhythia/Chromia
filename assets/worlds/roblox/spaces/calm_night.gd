extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Calm Night" (CalmNight): stars that spin, bob and slowly
# glow gold under the moon; every hit sends an outline ring out from a star in
# the note colour.

var stars = [] # [model, start pivot, main part, main size]

func _init():
	slug = "calm_night"

func space_init():
	var s = space_obj.child("Stars")
	if s == null:
		return
	for c in s.kids():
		var main = c.child("Main")
		if main != null:
			stars.append([c, c.get_pivot(), main, main.size])
	for i in range(stars.size()):
		after((i + 1) * 0.5, self, "_glow", [stars[i][2]])

func _glow(main):
	if is_instance_valid(main):
		tween(main, {"Color": Color8(248, 203, 53)}, 2.0, "Linear", "Out", -1, true)

func space_update(_dt):
	var t = now()
	var k = fmod(t, 1.0)
	for i in range(stars.size()):
		var e = stars[i]
		var bob = sin((k - (i + 1) * 0.15) * PI * 2) * 0.1
		var r: Transform = e[1] * cfa(0, 0, deg2rad(t * 35 + (i + 1) * 28))
		r.origin += Vector3(0, bob, 0)
		e[0].pivot_to(r)

func space_hit(col):
	var tpl = assets_obj.child("Outline")
	if tpl == null or stars.empty():
		return
	var e = stars[rand_int(0, stars.size() - 1)]
	var o = tpl.clone_obj()
	o.set_color(col)
	o.set_size(e[3])
	o.set_parent_obj(e[0])
	o.set_cframe(e[2].get_cframe())
	var size: Vector3 = o.size
	on_done(tween(o, {"Size": Vector3(size.x + 5, size.y + 5, 0.001)}, 1.2, "Quint", "Out"), o, "destroy")
	tween(o, {"Transparency": 1.0}, 1.2, "Quint", "Out")
