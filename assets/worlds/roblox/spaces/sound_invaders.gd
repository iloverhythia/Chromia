extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Sound Invaders" (SoundInvadersScript): space invaders fly
# in on both sides and the two blasters shoot them down as you hit notes; every
# hit tints the light glow and the star streaks with the note colour.
# (The original spawned one invader per note on screen; here one comes in per
# hit, and the next hit on that side shoots the oldest one.)

const BULLET_SPEED = 80.0
var blasters = []
var blaster_cols = []
var blaster_t = [1.0, 1.0]
var invader_tpls = []
var invaders = [[], []]
var frames = []
var bullets = [] # [mesh, start, invader, side, travelled]
var particles = []
var side = 0
var bullet_mat: SpatialMaterial

func _init():
	slug = "sound_invaders"

func space_init():
	for n in ["BlasterL", "BlasterR"]:
		var b = space_obj.at("Blasters/" + n)
		if b != null:
			blasters.append(b)
			blaster_cols.append(b.color)
	var p = space_obj.child("Particles")
	particles = p.kids() if p != null else []
	bullet_mat = SpatialMaterial.new()
	bullet_mat.flags_unshaded = true
	if not env_effects:
		for b in blasters:
			b.visible = false

func space_load():
	var ex = space_obj.child("Explosion")
	if ex != null:
		var i = 1
		while true:
			var f = ex.child(str(i))
			if f == null:
				break
			f.visible = false
			frames.append(f)
			i += 1
	var inv = space_obj.child("Invaders")
	if inv != null:
		for c in inv.kids():
			c.visible = false
			invader_tpls.append(c)

func _spawn_invader(s: int):
	if invader_tpls.empty():
		return
	var m = invader_tpls[rand_int(0, invader_tpls.size() - 1)].clone_obj()
	m.visible = true
	m.set_parent_obj(space_obj.child("Invaders"))
	var z = (22.0 if s == 0 else -22.0) + (rand() * 6 - 3)
	m.set_position(Vector3(-62 - rand() * 10, -1 + rand() * 8, z))
	invaders[s].append(m)

func space_update(dt):
	if not env_effects:
		return
	for i in range(blasters.size()):
		blaster_t[i] = min(blaster_t[i] + dt, 0.2)
		blasters[i].set_color(blaster_cols[i].linear_interpolate(Color(0.5, 0, 0), sin(PI * blaster_t[i] / 0.2)))
	for s in [0, 1]:
		var keep = []
		for m in invaders[s]:
			if not is_instance_valid(m):
				continue
			m.set_position(m.get_position() + Vector3(dt * 30, 0, 0))
			if m.get_position().x > -22:
				# got through: the blaster flinches
				if s < blaster_t.size():
					blaster_t[s] = 0.1 - abs(blaster_t[s] - 0.1)
				m.destroy()
			else:
				keep.append(m)
		invaders[s] = keep
	var live = []
	for b in bullets:
		var mi: MeshInstance = b[0]
		var inv = b[2]
		if not is_instance_valid(inv):
			mi.queue_free()
			continue
		b[4] += dt * BULLET_SPEED
		var pos: Vector3 = b[1] + Vector3(-b[4], 0, 0)
		var target: Vector3 = inv.get_position()
		pos.y = lerp(b[1].y, target.y, clamp(b[4] / max(1.0, b[1].x - target.x), 0, 1))
		pos.z = lerp(b[1].z, target.z, clamp(b[4] / max(1.0, b[1].x - target.x), 0, 1))
		if pos.x <= target.x:
			_explode(target, mi.get_meta("col"))
			invaders[b[3]].erase(inv)
			inv.destroy()
			mi.queue_free()
			continue
		mi.transform.origin = pos
		live.append(b)
	bullets = live

func space_hit(col):
	group_color("light", col)
	for p in particles:
		for n in ["Speed", "Star"]:
			var e = p.child(n)
			if e != null:
				e.set_emitter_color(col)
	if not env_effects or blasters.empty():
		return
	var s = side
	side = (side + 1) % blasters.size()
	_spawn_invader(s)
	if invaders[s].size() < 2:
		return
	var target = invaders[s][0]
	var b = blasters[s]
	var mi = MeshInstance.new()
	var cm = CubeMesh.new()
	cm.size = Vector3(1, 0.2, 0.2)
	mi.mesh = cm
	var m: SpatialMaterial = bullet_mat.duplicate()
	m.albedo_color = col * 1.4
	mi.material_override = m
	mi.set_meta("col", col)
	mi.transform.origin = b.get_position()
	rbx_root.add_child(mi)
	bullets.append([mi, b.get_position(), target, s, 0.0])

func _explode(at: Vector3, col: Color):
	_explode_frame(0, at, col)

func _explode_frame(i: int, at: Vector3, col: Color):
	if i >= frames.size():
		return
	var f = frames[i].clone_obj()
	f.visible = true
	for d in f.desc():
		if d.is_part():
			d.set_color(col)
	f.set_parent_obj(space_obj.child("Explosion"))
	var p: Transform = f.get_pivot()
	p.origin = at
	f.pivot_to(p)
	after(0.075, f, "destroy")
	after(0.075, self, "_explode_frame", [i + 1, at, col])
