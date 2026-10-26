extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Shooting Stars" (ShootingStars): clouds drift round above
# a pink sea of clouds, and every hit sends a shooting star (with a trail in the
# note colour) falling across the sky.

var stars = []

func _init():
	slug = "shooting_stars"

func space_update(dt):
	var t = now()
	var live = []
	for s in stars:
		if not is_instance_valid(s):
			continue
		live.append(s)
		var dy = -50.0 * dt
		var dz = dy * 0.3 * sin(t)
		s.set_cframe(s.get_cframe() * cf(Vector3(0, dy, dz)))
	stars = live
	for n in [["Clouds", -0.08], ["CloudsLower", 0.05]]:
		var m = space_obj.child(n[0])
		if m != null:
			m.pivot_to(m.get_pivot() * cfa(0, n[1] * dt, 0))

func space_hit(col):
	var tpl = assets_obj.child("FallingStar")
	var sp = space_obj.child("SpawnPoints")
	if tpl == null or sp == null or sp.kids().empty():
		return
	var s = tpl.clone_obj()
	var at = pick(sp.kids())
	s.set_color(col)
	var tr = s.child("Trail")
	if tr != null:
		tr.set_color(col)
	s.set_parent_obj(space_obj.child("Temp"))
	s.set_cframe(at.get_cframe())
	stars.append(s)
	after(5.0, s, "destroy")
