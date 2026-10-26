extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "The Speaker" (TheSpeakerDecorScript): the speaker cones
# pump with the music's loudness in the note colour, the particles take the note
# colour, and a light streak shoots past you on every hit.

var speakers = [] # [cone model, inner size, middle size, outer size, big?]
var emitters = []

func _init():
	slug = "the_speaker"

func space_init():
	var em = space_obj.child("Emitters")
	if em != null:
		emitters = find_all(em, "ParticleEmitter")
	for kind in ["Small", "Big"]:
		var f = space_obj.at("SpeakerBox/Speakers/" + kind)
		if f == null:
			continue
		for v in f.kids():
			var a = v.child("Inner")
			var b = v.child("Middle")
			var c = v.child("Outer")
			if a != null and b != null and c != null:
				speakers.append([v, a.size, b.size, c.size, kind == "Big"])

func space_update(_dt):
	var col = get_color()
	var l = loudness()
	var big = min(1.0, l / 700.0) * 0.4 + 0.6
	var small = min(1.0, l / 500.0) * 0.4 + 0.6
	var c1 = Color(0, 0, 0).linear_interpolate(col, 0.125)
	var c2 = Color(0, 0, 0).linear_interpolate(col, 0.5)
	for s in speakers:
		var k: float = big if s[4] else small
		var v = s[0]
		var inner = v.child("Inner")
		var middle = v.child("Middle")
		var outer = v.child("Outer")
		inner.set_size(s[1] * k)
		middle.set_size(s[2] * k)
		outer.set_size(s[3] * k)
		inner.set_color(c1)
		middle.set_color(c2)
		outer.set_color(col)
	for e in emitters:
		if e.extra.get("last_col") != col:
			e.extra["last_col"] = col
			e.set_emitter_color(col)

func space_hit(col):
	var tpl = assets_obj.child("Particle")
	if tpl == null:
		return
	var p = tpl.clone_obj()
	p.set_position(Vector3(-85 - rand() * 20, 0, 0))
	p.set_color(col)
	p.set_parent_obj(space_obj.child("Particles"))
	on_done(tween(p, {"CFrame": cf(Vector3(16, 0, 0)), "Transparency": 0.0}, 0.5, "Quad", "Out"), p, "destroy")
