extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Tronic" (TronicSpace): a Tron-style grid road scrolling
# toward you, floating spheres; the neons, light beams and particles take the
# note colour on every hit.

var beams = []
var spheres = [] # [part, start cframe]
var emitters = []
var grid
var cs_box

func _init():
	slug = "tronic"

func space_init():
	var b = space_obj.at("Dynamic/Beams")
	beams = b.kids() if b != null else []
	var s = space_obj.at("Dynamic/Spheres")
	if s != null:
		for c in s.kids():
			spheres.append([c, c.get_cframe()])
	var e = space_obj.child("Emitters")
	if e != null:
		emitters = find_all(e, "ParticleEmitter")
	grid = space_obj.at("Dynamic/Grid")
	cs_box = value_box(Color8(0, 196, 255), self, "_seq_color")
	_set_color(Color8(0, 196, 255))
	_seq_color(Color8(0, 196, 255))

func _set_color(c: Color):
	group_color("neon", c)
	for sp in spheres:
		sp[0].set_color(c)

func _seq_color(c):
	for b in beams:
		b.set_color(c)
	for e in emitters:
		e.set_emitter_color(c)

func space_update(dt):
	var t = now()
	for e in spheres:
		var p = e[0]
		var start: Transform = e[1]
		var a = fmod(t / 2.5, 1.0) * PI * 2
		var pos: Vector3 = start.origin + up_vector(start) * sin(a) * 10
		var r: Transform = rot_only(p.get_cframe())
		var dz = sign(p.get_position().z)
		r = r * cfa(deg2rad(dt * 15), deg2rad(dt * 25 * dz), 0)
		r.origin = pos
		p.set_cframe(r)
	if grid != null:
		var g: Transform = grid.get_pivot()
		g.origin.x = rmod(g.origin.x + dt * 50, 169.475)
		grid.pivot_to(g)

func space_hit(col):
	tween(group_obj("neon"), {"Color": col}, 0.15)
	for sp in spheres:
		tween(sp[0], {"Color": col}, 0.15)
	tween(cs_box, {"Value": col}, 0.15)
