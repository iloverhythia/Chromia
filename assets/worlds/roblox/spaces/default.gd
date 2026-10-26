extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Default" (DefaultDecorScript): squares that slide toward
# you, and coloured waves along both sides on every hit (bigger when hits come fast).

var squares = []
var despawn = 10.0
var last_hit = 0.0

func _init():
	slug = "default"

func space_init():
	var holder = space_obj.child("Squares")
	for _i in range(6):
		var tpl = assets_obj.child("Square2")
		if squares.size() % 3 == 0:
			tpl = assets_obj.child("Square1")
		if tpl == null or holder == null:
			break
		var s = tpl.clone_obj()
		s.set_parent_obj(holder)
		s.set_cframe(cf(Vector3(-squares.size() * 100 + despawn, 3, 0)) * cfa(PI / 4, 0, 0))
		squares.append(s)
	space_update(0)

func space_update(dt):
	var mv = 100.0 * get_speed() * dt
	var back = despawn - squares.size() * 100
	var span = abs(back - 100)
	for s in squares:
		s.set_color(get_color())
		var x: float = s.get_position().x + mv
		if despawn <= x:
			x += back
		s.set_transparency(clamp((100 - x) / span, 0, 1))
		var p: Vector3 = s.get_position()
		p.x = x
		s.set_position(p)

func space_hit(col):
	var t = now()
	var d = t - last_hit
	last_hit = t
	var v = clamp(1.0 / max(d, 0.0001), 0, 20) / 12.0 + 1
	_spawn_waves(col, clamp(v, 1, 3) * 0.95)

func _spawn_waves(col: Color, mult: float):
	var sp = get_speed()
	if sp == 0:
		return
	var holder = space_obj.child("Waves")
	for n in ["WaveLeft", "WaveRight"]:
		var tpl = assets_obj.child(n)
		if tpl == null:
			continue
		var w = tpl.clone_obj()
		w.set_size(w.size * Vector3(1, mult, 1))
		var img = w.at("SurfaceGui/ImageLabel")
		if img != null:
			img.set_color(col)
		w.set_parent_obj(holder)
		var p: Vector3 = w.get_position()
		on_done(tween(w, {"CFrame": cf(Vector3(-75, p.y, p.z)), "Transparency": 1.0}, 2.0 / sp, "Quint", "Out"), w, "destroy")
		if img != null:
			tween(img, {"ImageTransparency": 1.0}, 2.0 / sp, "Quint", "Out")
		tween(w, {"Size": tpl.size}, 0.4 / sp, "Sine", "In")
