extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Cat Shades" (CatShades): a big cat in sunglasses over the
# water; its eyes blink now and then and, with the smoke, light and particles,
# take the note colour on every hit.

var eyes
var eye_size = Vector3.ONE
var light
var emitters = []
var blinking = false

func _init():
	slug = "cat_shades"

func space_init():
	eyes = space_obj.at("Dynamic/Neons/Cat Eyes")
	if eyes != null:
		eye_size = eyes.size
	light = space_obj.at("Dynamic/Light/Part/PointLight")
	var p = space_obj.at("Dynamic/Particles")
	if p != null:
		emitters = find_all(p, "ParticleEmitter")

func space_load():
	var w = folder.child("WaterPart")
	if w != null:
		w.visible = false
		add_water(w.get_cframe(), w.size)

func space_update(_dt):
	_blink()

func space_hit(col):
	group_color("smoke", col)
	for e in emitters:
		e.set_emitter_color(col)
	if eyes != null:
		eyes.set_color(col)
	if light != null:
		light.set_color(col)

func _blink():
	if blinking or eyes == null:
		return
	blinking = true
	on_done(tween(eyes, {"Size": eye_size * Vector3(1, 0.15, 1)}, 0.075, "Sine", "In"), self, "_blink_open")

func _blink_open():
	after(0.05, self, "_blink_open2")

func _blink_open2():
	on_done(tween(eyes, {"Size": eye_size}, 0.075, "Sine", "Out"), self, "_blink_wait")

func _blink_wait():
	after(0.2 + rand() * 3, self, "_blink_done")

func _blink_done():
	blinking = false
