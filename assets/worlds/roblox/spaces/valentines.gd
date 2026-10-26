extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Valentines" (ValentinesScript): a boat rocking on the
# water; hearts burst from the emitters in the note colour on every hit.

var boat
var boat_cf = Transform()
var hit_emitters = []

func _init():
	slug = "valentines"

func space_init():
	boat = space_obj.at("Decor/Boat")
	if boat != null:
		boat_cf = boat.get_pivot()
	var he = space_obj.child("HitEmitters")
	if he != null:
		hit_emitters = find_all(he, "ParticleEmitter")

func space_load():
	add_water(cf(Vector3(0, -9, 0)), Vector3(480, 13, 480))

func space_update(_dt):
	if boat == null:
		return
	var t = now()
	boat.pivot_to(boat_cf * cfa(deg2rad(-sin(t) * 2), 0, deg2rad(cos(t) * 0.75)))

func space_hit(col):
	for e in hit_emitters:
		e.set_enabled(true)
		after(0.06, self, "_hit_off", [e, col])

func _hit_off(e, col):
	if is_instance_valid(e):
		e.set_emitter_color(col)
		e.set_enabled(false)
