extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Vaporwave" (VaporwaveDecorScript): scrolling grid floor
# and ceiling in the note colour, and cubes / spheres / pyramids drifting up on
# both sides (extra small ones in the note colour on every hit, pulsing on beats).

var grids = []
var shape_timer = 2.0
var size_mult = 1.0

func _init():
	slug = "vaporwave"

func space_init():
	var g = space_obj.child("Grids")
	grids = g.kids() if g != null else []
	for p in grids:
		var pos: Vector3 = p.get_position()
		p.extra["y"] = pos.y
		p.extra["z"] = pos.z
		_grid_loop(p)
	group_color("img", get_color())

func _grid_loop(p):
	if not is_instance_valid(p):
		return
	p.set_cframe(cf(Vector3(-30, p.extra.y, p.extra.z)))
	var tw = tween(p, {"CFrame": cf(Vector3(-14, p.extra.y, p.extra.z))}, 0.64 / max(get_speed(), 0.01), "Linear")
	on_done(tw, self, "_grid_loop", [p])

func space_update(dt):
	group_color("img", get_color())
	var shapes = space_obj.child("Shapes")
	if shapes != null:
		for v in shapes.kids():
			v.set_color(get_color())
			v.set_size(v.extra.get("StartSize", v.size) * size_mult)
	size_mult = max(1.0, size_mult - dt * 4)
	shape_timer += dt
	if shape_timer >= 2:
		shape_timer -= 2
		_spawn_shape(true, null)
		_spawn_shape(false, null)

func space_hit(col):
	_spawn_shape(true, col)
	_spawn_shape(false, col)

func space_beat():
	size_mult = 1.75

func _spawn_shape(side: bool, col):
	var kind: String = ["Cube", "Sphere", "Tetrahedron"][rand_int(0, 2)]
	var tpl = assets_obj.child(kind)
	if tpl == null:
		return
	var s = tpl.clone_obj()
	s.set_transparency(1)
	s.set_size(s.size * (0.25 + rand() * 0.75) / 1.25)
	s.extra["StartSize"] = s.size
	var zs = 15.0 if side else -15.0
	s.set_cframe(cf(Vector3(-(15 + rand() * 70), -22, zs * (0.75 + rand() * 3))))
	if col != null:
		s.set_color(col)
		s.set_size(s.size * 0.5)
		s.set_parent_obj(space_obj.child("HitShapes"))
	else:
		s.set_parent_obj(space_obj.child("Shapes"))
	var dur = (2.0 if col != null else 6.0) / max(get_speed(), 0.01)
	var target: Transform = s.get_cframe() * cfa((rand() * 2 - 1) * PI, (rand() * 2 - 1) * PI, (rand() * 2 - 1) * PI)
	target.origin += Vector3(0, 44, 0)
	on_done(tween(s, {"CFrame": target}, dur, "Linear"), s, "destroy")
	on_done(tween(s, {"Transparency": 0.0}, dur / 2, "Linear", "Out"), self, "_fade_out", [s, dur / 2])

func _fade_out(s, d: float):
	if is_instance_valid(s):
		tween(s, {"Transparency": 1.0}, d, "Linear", "In")
