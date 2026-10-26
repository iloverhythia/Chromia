extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Lucky" (LuckyScript): on every hit a lucky charm pops up
# from one of the pads, spinning as it rises and falls back.

var pads = []
var last_pad = 0
var hit_model
var flying = [] # [model, start point, up direction, time]

func _init():
	slug = "lucky"

func space_init():
	var p = space_obj.child("SpawnPads")
	pads = p.kids() if p != null else []
	last_pad = pads.size()

func space_load():
	var h = space_obj.child("Hit")
	if h != null and not h.kids().empty():
		hit_model = h.kids()[0]
		hit_model.visible = false

func space_hit(_col):
	if pads.empty() or hit_model == null:
		return
	var i = last_pad % pads.size()
	var pad = pads[i]
	last_pad = i + 1
	var s: Vector3 = pad.size
	var at: Vector3 = pad.get_cframe().xform(Vector3(rand() * s.x - s.x / 2, rand() * s.y - s.y / 2, rand() * s.z - s.z / 2))
	var m = hit_model.clone_obj()
	m.visible = true
	m.set_parent_obj(space_obj.child("Hit"))
	flying.append([m, at, up_vector(pad.get_cframe()), 0.0])

func space_update(dt):
	var live = []
	for f in flying:
		var m = f[0]
		if not is_instance_valid(m):
			continue
		f[3] += dt
		var t: float = f[3]
		if t >= 2.0:
			m.destroy()
			continue
		live.append(f)
		var k = sin(t / 2 * PI)
		var off: Vector3 = f[2] * 10 * k
		var pos: Vector3 = f[1] + off
		m.pivot_to(cf_look(pos, pos + f[2]) * cfa(0, 0, PI / 2) * cfa(t / 2 * 5 * PI * 2, PI / 2, 0))
	flying = live
