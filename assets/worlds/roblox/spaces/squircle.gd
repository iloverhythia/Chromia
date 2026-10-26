extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Squircle" (SquircleScript): a turning squircle ringed by
# bars that jump with the music like an equaliser, floating squircles that flip
# around; on every hit the colour ripples out through the squircles and bars.

var squircles = []
var squircle
var bar_sets = [] # each: array of [bar, offset]
var values = []
var last_time = 0.0

func _init():
	slug = "squircle"

func space_init():
	squircle = space_obj.child("Squircle")
	var bs = space_obj.child("BarsSets")
	var r = RandomNumberGenerator.new()
	r.seed = 100
	if bs != null and squircle != null:
		var inv: Transform = squircle.get_cframe().affine_inverse()
		for set in bs.kids():
			var arr = []
			for b in set.kids():
				if not b.is_part():
					continue
				var bc: Transform = b.get_cframe()
				var base: Transform = bc
				base.origin -= look_vector(bc) * b.size.z / 2
				arr.append([b, inv * base])
			arr.sort_custom(self, "_by_name")
			for i in range(arr.size()):
				var j = r.randi_range(0, arr.size() - 1)
				var tmp = arr[i]
				arr[i] = arr[j]
				arr[j] = tmp
			bar_sets.append(arr)
			values = []
			for _i in range(arr.size() + 1):
				values.append(0.0)
	var sq = space_obj.child("Squircles")
	squircles = sq.kids() if sq != null else []
	squircles.sort_custom(self, "_by_x")
	var r2 = RandomNumberGenerator.new()
	r2.seed = 100
	for v in squircles:
		var d = -1.0 if r2.randf() > 0.5 else 1.0
		r2.randf()
		var period = 1.5 + r2.randf()
		v.set_size(v.size * Vector3(1, 1, 2))
		after(period / 2, self, "_spin", [v, d, period])

func _by_name(a, b):
	return a[0].rname < b[0].rname

func _by_x(a, b):
	return a.get_position().x < b.get_position().x

func _spin(v, d: float, period: float):
	if is_instance_valid(v):
		tween(v, {"CFrame": v.get_cframe() * cfa(0, 0, deg2rad(90 * d))}, period, "Sine", "InOut", -1)

func space_update(dt):
	_put_value(loudness())
	if squircle != null:
		var a = fmod(now() * 10 / 360.0, 1.0) * PI * 2
		squircle.set_cframe(Transform(angles(0, PI / 2, a), squircle.get_position()))

func _set_bar(i: int, z: float):
	for set in bar_sets:
		if i >= set.size():
			continue
		var e = set[i]
		var b = e[0]
		var size = Vector3(b.size.x, b.size.y, z)
		var c: Transform = squircle.get_cframe() * e[1]
		c.origin += look_vector(c) * z / 2
		b.set_size(size)
		b.set_cframe(c)

func _put_value(v: float):
	if bar_sets.empty() or squircle == null:
		return
	if now() - last_time <= 1.0 / 62.0:
		return
	last_time = now()
	values[values.size() - 1] = v
	var total = 0.0
	var top = 0.0
	for i in range(1, values.size()):
		var x: float = max(800.0 * 0.7, values[i])
		total += x
		top = max(top, x)
	var avg: float = (total / bar_sets[0].size() + top) / 2
	for i in range(bar_sets[0].size()):
		values[i] = values[i + 1]
		_set_bar(i, max(0.05, (values[i] / avg if avg > 0 else 0.0) * 7))

func space_hit(col):
	if squircle != null:
		tween(squircle, {"Color": col}, 0.2, "Sine", "Out")
	var bs = space_obj.at("BackSprite/Decal")
	if bs != null:
		tween(bs, {"Color3": col}, 0.2, "Sine", "Out")
	for i in range(squircles.size()):
		after(int(i / 2) * 0.016, self, "_flash_squircle", [squircles[i], col])
	var c2 = col.linear_interpolate(Color(1, 1, 1), 0.25)
	if bar_sets.empty():
		return
	for i in range(bar_sets[0].size()):
		after(i * 0.016, self, "_flash_bars", [i, col])

func _flash_squircle(v, col):
	if is_instance_valid(v):
		v.set_transparency(-4)
		tween(v, {"Transparency": -1.5, "Color": col}, 0.2, "Sine", "In")

func _flash_bars(i: int, col):
	for set in bar_sets:
		if i < set.size():
			tween(set[i][0], {"Color": col}, 0.2, "Sine", "Out")
