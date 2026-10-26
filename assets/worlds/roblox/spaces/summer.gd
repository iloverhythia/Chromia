extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Summer" (SummerSpace): a beach at sunset with leaves
# gently swaying in the breeze.

var leaves = [] # [part/model, start cframe]
var passed = 0.0

func _init():
	slug = "summer"

func space_init():
	var s = space_obj.at("Effects/BackSprite/Decal")
	if s != null:
		s.set_color(Color8(255, 149, 42))
	var d = space_obj.child("Dynamic")
	if d != null:
		for c in d.kids():
			leaves.append([c, c.get_cframe()])

func space_update(dt):
	var step = rate_limit("summer", 30, dt)
	if step <= 0:
		return
	passed += step * 0.06
	var i = 0
	for e in leaves:
		var a = sin(fmod(passed + i * 0.4, 1.0) * PI * 2)
		e[0].set_cframe(e[1] * cfa(0, 0, deg2rad(a * 4)))
		i += 1
