extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Torii" (Torii): a neon torii gate in the dark; on every
# hit the neon takes the note colour and a random warning sign or word flashes
# up, shaking, then fades.

var stuff = [] # groups of parts that flash together
var shaking = [] # [part, start cframe]
var neon_words = [] # word / sign parts that are also neon
var particles

func _init():
	slug = "torii"

func space_init():
	for f in ["DangerSigns", "Words"]:
		var o = space_obj.child(f)
		if o == null:
			continue
		for c in o.kids():
			var parts = []
			for p in c.kids():
				parts.append(p)
			stuff.append(parts)
	for g in stuff:
		for p in g:
			p.set_transparency(1)
			if p.rname == "Neon":
				neon_words.append(p)
			if p.is_part():
				shaking.append([p, p.get_cframe()])
	particles = space_obj.at("Particles/Colored/ParticleEmitter")

func space_update(dt):
	if rate_limit("torii", 60, dt) <= 0:
		return
	for e in shaking:
		var v = Vector3(rand() * 2 - 1, rand() * 2 - 1, rand() * 2 - 1).normalized() * 0.7
		e[0].set_cframe(moved(e[1], v))

func space_hit(col):
	tween(group_obj("neon"), {"Color": col}, 1.0, "Quint", "Out")
	for p in neon_words:
		tween(p, {"Color": col}, 1.0, "Quint", "Out")
	if not stuff.empty():
		for p in stuff[rand_int(0, stuff.size() - 1)]:
			p.set_transparency(-1)
			tween(p, {"Transparency": 1.0}, 1.0, "Quint", "Out")
	if particles != null:
		particles.set_emitter_color(col)
