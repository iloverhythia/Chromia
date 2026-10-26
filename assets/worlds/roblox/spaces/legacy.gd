extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Legacy" (LegacySpace): the old Sound Space look - a row of
# slowly rocking squares down a long platform; the platform edges, squares and
# sprites follow the note colour, waves run along the sides on every hit and
# the fog tints toward the note colour.

var squares = [] # [part, image, base angle]
var last_color = null
var last_hit = 0.0
var emitters = []

func _init():
	slug = "legacy"

func space_init():
	var tpl = assets_obj.child("Square")
	if tpl != null:
		for i in range(1, 31):
			var x = -i * 20.0
			var s = tpl.clone_obj()
			var img = s.at("SurfaceGui/ImageLabel")
			if img != null:
				img.set_transparency(max(0.0, abs(x / 20.0) - 10) / 20.0)
			var ang = i * 10.0 + 45
			s.set_parent_obj(space_obj)
			s.set_cframe(Transform(angles(deg2rad(ang), 0, 0), Vector3(x, 3, 0)))
			var box = value_box(ang, self, "_angle_changed")
			box.set_meta("part", s)
			squares.append([s, img, ang, box])
			after((i - 1) / 30.0 * 2.5, self, "_rock", [squares.size() - 1, true])
	var e = space_obj.child("Emitters")
	if e != null:
		emitters = find_all(e, "ParticleEmitter")

func _angle_changed(_v):
	pass

func _rock(i: int, up: bool):
	var s = squares[i]
	var target: float = s[2] + 8 if up else s[2]
	var from: float = s[2] if up else s[2] + 8
	var box = s[3]
	var tw = tween(box, {"Value": target}, 3.5, "Sine", "InOut")
	tw["square"] = i
	on_done(tw, self, "_rock", [i, not up])
	box.value = from

func space_update(_dt):
	for s in squares:
		var p = s[0]
		if is_instance_valid(p):
			p.set_cframe(Transform(angles(deg2rad(s[3].value), 0, 0), p.get_position()))
	var c = get_color()
	if c == last_color:
		return
	last_color = c
	var sb = space_obj.at("Platform/SelectionBox")
	if sb != null:
		sb.set_color(c)
	for n in ["Platform/SideLeft", "Platform/SideRight"]:
		var o = space_obj.at(n)
		if o != null:
			o.set_color(c)
	for s in squares:
		if s[1] != null:
			s[1].set_color(c)
	group_color("spr", c)
	for e in emitters:
		e.set_emitter_color(c)

func space_hit(col):
	var t = now()
	var d = t - last_hit
	last_hit = t
	var v = clamp(1.0 / max(d, 0.0001), 0, 20) / 10.0 + 1
	tween(lighting, {"FogColor": Color(col.r * 0.2, col.g * 0.2, col.b * 0.2)}, 0.8)
	_spawn_waves(col, clamp(v, 1, 3.5) * 0.95)

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
		tween(w, {"Size": tpl.size}, 0.4 / sp, "Sine", "In")
		on_done(tween(w, {"CFrame": cf(Vector3(-200, p.y, p.z))}, 2.0 / sp, "Linear"), w, "destroy")
