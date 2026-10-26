extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Phantom Seas" (PhantomSeasScript): a ghost ship rocking
# on a stormy sea; on every hit lightning strikes somewhere and the ship's glow
# changes to the note colour (keeping each part's own brightness).
# (The flags' animation is private on Roblox, so the flags hang still.)

var ship
var ship_cf = Transform()
var pool = [] # [node part, lightning model, [glow decals], bolt]
var spin_decals = [] # BigSpin's own decals: [decal, sat, val]

func _init():
	slug = "phantom_seas"

func space_init():
	ship = space_obj.child("Ship")
	if ship != null:
		ship_cf = ship.get_pivot()
	var nodes = space_obj.child("Nodes")
	var holder = space_obj.child("Lightnings")
	var kinds: Array = assets_obj.kids() if assets_obj != null else []
	if nodes != null and holder != null and not kinds.empty():
		for v in nodes.kids():
			v.set_transparency(1)
			var l = kinds[rand_int(0, kinds.size() - 1)].clone_obj()
			l.set_parent_obj(holder)
			l.pivot_to(v.get_cframe())
			var glow = []
			for d in l.desc():
				if d.rclass == "Decal":
					d.set_transparency(1)
					glow.append(d)
				elif d.is_part():
					d.set_transparency(1)
			pool.append([v, l, glow, l.child("Bolt")])
	var bs = space_obj.at("Sprites/BigSpin")
	if bs != null:
		for d in bs.desc():
			if d.rclass == "Decal":
				var hsv = d.color
				spin_decals.append([d, hsv.s, hsv.v])

func space_load():
	add_water(cf(Vector3(-7, -19, 0)), Vector3(7500, 14, 7500))
	_tween_ship(Color8(46, 255, 158))

func space_update(dt):
	var t = now()
	var a = sin(deg2rad(fmod(t * 60, 360)))
	var b = sin(deg2rad(fmod(t * 30, 360)))
	if ship != null:
		var p: Transform = ship_cf * cfa(deg2rad(a * 2.5), 0, 0) * cfa(0, 0, deg2rad(b * 4))
		p.origin += Vector3(0, a - 1, 0)
		ship.pivot_to(p)
	var spin = space_obj.at("Sprites/BigSpin")
	if spin != null:
		spin.set_cframe(spin.get_cframe() * cfa(deg2rad(dt * 60), 0, 0))

func space_hit(col):
	_tween_lightning(col)
	_tween_ship(col)

func _tween_ship(c: Color):
	for g in groups.keys():
		var gr: Dictionary = groups[g]
		if gr.kind == "hsv" or gr.kind == "hsvd":
			tween(group_obj(g), {"Color": Color.from_hsv(c.h, c.s * gr.s, c.v * gr.v)}, 0.2, "Sine", "In")
	for e in spin_decals:
		tween(e[0], {"Color3": Color.from_hsv(c.h, c.s * e[1], c.v * e[2])}, 0.2, "Sine", "In")

func _tween_lightning(col: Color):
	if pool.empty():
		return
	var e = pool[rand_int(0, pool.size() - 1)]
	e[1].pivot_to(e[0].get_cframe() * cfa(0, PI * 2 * rand(), 0))
	for d in e[2]:
		d.set_transparency(0)
		d.set_color(col)
		tween(d, {"Transparency": 1.0}, 0.35, "Sine", "In")
	if e[3] != null:
		e[3].set_transparency(0)
		e[3].set_color(col)
		tween(e[3], {"Transparency": 1.0}, 0.35, "Sine", "In")
