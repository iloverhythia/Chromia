extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Halloween" (HalloweenDecorScript): ghosts float up from
# the graves every half second (good and mad in turn), and a bat flies at you
# on every hit, tinted with the note colour.

var timer = 0.0
var ghost_count = 0
var good = true

func _init():
	slug = "halloween"

func space_update(dt):
	var holder = space_obj.child("Particles")
	if holder == null:
		return
	var cam = camera_pos()
	for v in holder.kids():
		var age: float = v.extra.get("Age", 0.0) + dt
		v.extra["Age"] = age
		var a = age * PI * 0.75
		var c = cos(a)
		var s = sin(a)
		var lv = look_vector(v.get_cframe())
		var pos: Vector3 = v.extra.SpawnPos + Vector3(0, age * 30, 0) + (lv - c * lv * 2) * 5
		v.set_cframe(cf_look(pos, Vector3(cam.x, pos.y, cam.z)) * cfa(0, PI / 2, 0) * cfa(-s * 0.3490658503988659, 0, 0))
		var t1 = 1.0 - clamp(age, 0, 1)
		var t2 = clamp(5 - age, 0, 1)
		v.set_transparency(max(t1, 1 - t2))
		v.set_size(v.extra.SpawnSize * max(t2, 0.001))
		if age >= 5:
			v.destroy()
	timer += dt
	if timer >= 0.5:
		timer -= 0.5
		_spawn_ghost()

func space_hit(col):
	_spawn_bat(Color(col.r / 2, col.g / 2, col.b / 2))

func _spawn_pos() -> Vector3:
	var sp: Array = space_obj.child("GhostSpawners").kids()
	if sp.empty():
		return Vector3(-100, 0, 0)
	var s = sp[ghost_count % sp.size()]
	var size: Vector3 = s.size
	return s.get_position() - size / 2 + Vector3(rand() * size.x, rand() * size.y, rand() * size.z)

func _spawn_ghost():
	var tpl = assets_obj.child("ghost_nice" if good else "ghost_mad")
	if tpl == null:
		return
	var g = tpl.clone_obj()
	var pos = _spawn_pos() - Vector3(0, 10, 0)
	g.set_cframe(cf_look(pos, camera_pos()) * cfa(0, PI / 2, 0))
	g.set_size(g.size * (1 + rand() * 1.5))
	g.extra["Age"] = 0.0
	g.extra["SpawnPos"] = pos
	g.extra["SpawnSize"] = g.size
	g.set_transparency(1)
	g.set_parent_obj(space_obj.child("Particles"))
	ghost_count += 1
	good = not good

func _spawn_bat(col: Color):
	var tpl = assets_obj.child("Bat")
	if tpl == null:
		return
	var a = rand() * PI
	var z = cos(a) * 12
	var y = sin(a) * 12 + 3
	var x = -50 - rand() * 20
	var b = tpl.clone_obj()
	var rot = cfa(-a + PI / 2, 0, 0.17453292519943295) * cfa(0, -PI / 2, 0)
	b.set_cframe(cf(Vector3(x, y, z)) * rot)
	b.set_color(col)
	b.set_parent_obj(space_obj.child("Bats"))
	on_done(tween(b, {"CFrame": cf(Vector3(16, y, z)) * rot, "Transparency": 0.0}, 1.25, "Quint", "Out"), b, "destroy")
