extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Cubic" (CubicScript): floating cubes tumbling slowly;
# every hit ripples a bright flash of the note colour through them.

var cubes = []
var sizes = []

func _init():
	slug = "cubic"

func space_init():
	var c = space_obj.child("Cubes")
	cubes = c.kids() if c != null else []
	cubes.sort_custom(self, "_by_x")
	var r = RandomNumberGenerator.new()
	r.seed = 100
	for v in cubes:
		var d1 = -1.0 if r.randf() > 0.5 else 1.0
		var d2 = sign(r.randf() - 0.5)
		r.randf()
		var period = 5 + r.randf() * 4
		var s = 12 + r.randf() * 24
		v.set_size(Vector3(s, s, s))
		sizes.append(v.size)
		after(period / 2, self, "_spin", [v, d1, d2, period])
	var bs = space_obj.at("BackSprite/Decal")
	if bs != null:
		bs.set_color(Color(1, 1, 1))
	for i in range(cubes.size()):
		cubes[i].set_color(Color(1, 1, 1))

func _by_x(a, b):
	return a.get_position().x < b.get_position().x

func _spin(v, d1: float, d2: float, period: float):
	if is_instance_valid(v):
		tween(v, {"CFrame": v.get_cframe() * cfa(deg2rad(90 * d1), deg2rad(d2 * 90), deg2rad(90 * d1))}, period, "Linear", "InOut", -1)

func space_hit(col):
	var bs = space_obj.at("BackSprite/Decal")
	if bs != null:
		tween(bs, {"Color3": col}, 0.2, "Sine", "In")
	for i in range(cubes.size()):
		after(int(i / 2) * 0.016, self, "_flash", [i, col])

func _flash(i: int, col):
	var v = cubes[i]
	if not is_instance_valid(v):
		return
	v.set_size(sizes[i] * 1.075)
	v.set_transparency(-10)
	tween(v, {"Color": col, "Size": sizes[i], "Transparency": -5.0}, 0.2, "Sine", "In")
