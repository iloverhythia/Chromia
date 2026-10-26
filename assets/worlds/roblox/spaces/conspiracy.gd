extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Conspiracy" (ConspiracyScript). Also the base of
# "Inverted Conspiracy" (black on white).
# Triangles, eyes and symbols bob up and down; the hexagram triangles turn
# slowly; every hit flashes one group in the note colour, sends a ring out from
# the middle and tints the background glow. Beats light up the hexagram.

var inverted = false
var hexa = []
var flickery = []
var particle_pick = 0
var rot_t = 0.0
var rot_started = false
var rot_base = []

func _init():
	slug = "conspiracy"

func _base_col() -> Color:
	return Color(0, 0, 0) if inverted else Color(0.15, 0.15, 0.15)

func space_init():
	var bs = space_obj.at("BackSprite/Decal")
	if bs != null:
		bs.set_color(Color(0, 0, 0) if inverted else Color(1, 1, 1))
	var rot = space_obj.child("Rotating")
	hexa = rot.kids() if rot != null else []
	for name in ["Triangles", "Symbols", "Eyes"]:
		var f = space_obj.at("Dynamic/" + name)
		if f != null:
			flickery += f.kids()
	for v in hexa:
		for p in v.kids():
			if p.is_part():
				p.set_color(_base_col())

func space_load():
	_run_dynamics("Triangles")
	after(0.3, self, "_run_dynamics", ["Eyes"])
	after(0.55, self, "_run_dynamics", ["Symbols"])
	after(0.55, self, "_start_rotation")

func _run_dynamics(name: String):
	var f = space_obj.at("Dynamic/" + name)
	if f == null:
		return
	for v in f.kids():
		for p in v.kids():
			if not p.is_part():
				continue
			p.set_transparency(0.0 if inverted else 0.85)
			tween(p, {"CFrame": moved(p.get_cframe(), Vector3(0, 1, 0))}, 1.5, "Sine", "InOut", -1, true)

func _start_rotation():
	rot_base = []
	for v in hexa:
		rot_base.append(Transform(angles(0, PI / 2, 0), v.get_pivot().origin))
	rot_started = true

func space_update(dt):
	if not rot_started:
		return
	# NumberValue 0 -> 1 -> 0 over 20 s each way, turning the hexagram
	rot_t += dt
	var k = fmod(rot_t, 40.0) / 20.0
	if k > 1.0:
		k = 2.0 - k
	for i in range(hexa.size()):
		var d = -1.0 if (i + 1) % 2 == 0 else 1.0
		hexa[i].pivot_to(rot_base[i] * cfa(0, 0, 2 * PI * d * k))

func space_hit(col):
	if env_effects and not hexa.empty():
		var pp = primary(hexa[particle_pick])
		if pp != null:
			var c = pp.clone_obj()
			c.set_transparency(-1)
			c.set_color(Color(col.r / 2, col.g / 2, col.b / 2))
			c.set_parent_obj(space_obj.child("Particles"))
			on_done(tween(c, {"Transparency": 1.0, "Size": c.size * 4}, 1.0, "Quint", "Out"), c, "destroy")
		particle_pick = (particle_pick + 1) % hexa.size()
	var bs = space_obj.at("BackSprite/Decal")
	if bs != null:
		tween(bs, {"Color3": col}, 0.2, "Sine", "Out")
	if flickery.empty():
		return
	var pick = flickery[rand_int(0, flickery.size() - 1)]
	for v in pick.kids():
		if not v.is_part():
			continue
		v.set_color(col)
		if inverted:
			tween(v, {"Color": Color(0, 0, 0)}, 0.35, "Sine", "In")
		else:
			v.set_transparency(0)
			tween(v, {"Transparency": 0.85, "Color": Color(1, 1, 1)}, 0.35, "Sine", "In")

func space_beat():
	for v in hexa:
		for p in v.kids():
			if p.is_part():
				p.set_color(Color(0.4, 0.4, 0.4))
				tween(p, {"Color": _base_col()}, 1.5, "Sine", "InOut", -1, true)
