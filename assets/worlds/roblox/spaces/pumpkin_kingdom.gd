extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Pumpkin Kingdom" (PumpkinKingdomScript): lanterns turn
# and bob, pumpkins float up and down; the pumpkins' glow and the sprites take
# the note colour on every hit.

var pumpkins = [] # [model, start pivot, index]
var lanterns = []

func _init():
	slug = "pumpkin_kingdom"

func space_init():
	group_color("obj", Color8(218, 133, 65))
	group_color("objd", Color8(218, 133, 65))
	var i = 1
	var p = space_obj.at("Dynamic/Pumpkins")
	if p != null:
		for c in p.kids():
			pumpkins.append([c, c.get_pivot(), i])
			i += 1
	i = 1
	var l = space_obj.at("Dynamic/Lanterns")
	if l != null:
		for c in l.kids():
			lanterns.append([c, c.get_pivot(), i])
			i += 1

func space_update(dt):
	var t = now()
	for e in lanterns:
		var m = e[0]
		var base: Transform = e[1]
		var i: int = e[2]
		var dir = -1.0 if i % 2 == 0 else 1.0
		var r: Transform = rot_only(m.get_pivot() * cfa(0, deg2rad(dt * (15 * (1 + i / 3.0 * 0.5)) * dir), 0))
		var a = fmod(t / 2.5, 1.0) * PI * 2 + deg2rad(i * 40 + 45)
		r.origin = base.origin + up_vector(base) * sin(a) * 2
		m.pivot_to(r)
	for e in pumpkins:
		var m = e[0]
		var base: Transform = e[1]
		var i: int = e[2]
		var r: Transform = rot_only(m.get_pivot())
		var a = fmod(t / 3.0, 1.0) * PI * 2 + deg2rad(i * 60)
		r.origin = base.origin + up_vector(base) * sin(a) * 3
		m.pivot_to(r)

func space_hit(col):
	tween(group_obj("obj"), {"Color": col}, 0.15)
	tween(group_obj("objd"), {"Color": col}, 0.15)
