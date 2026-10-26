extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Palm Trees" (PalmTreeScript): a neon road with palm trees
# and road lines scrolling past; the neon parts and the glow particles take the
# note colour on every hit.

const TREE_DIST = 107.871
const LINE_DIST = 50.0
const EMITTER_DIST = 400.0
var trees
var lines
var emitters
var e1
var e2
var timer = 0.0
var em_box

func _init():
	slug = "palm_trees"

func space_init():
	trees = space_obj.at("Decor/Palmtrees")
	lines = space_obj.at("Decor/RoadLines")
	emitters = space_obj.at("Emitters/Moving")
	e1 = space_obj.at("Emitters/Moving/Middle_Pink1/ParticleEmitter")
	e2 = space_obj.at("Emitters/Moving/Middle_Pink2/ParticleEmitter")
	em_box = value_box(Color8(255, 0, 190), self, "_emitter_color")
	group_color("pink", Color8(255, 0, 190))
	_emitter_color(Color8(255, 0, 190))

func _emitter_color(c):
	for e in [e1, e2]:
		if e != null:
			e.set_emitter_color(c, Color(0, 0, 0))

func space_update(dt):
	for pair in [[trees, TREE_DIST, 1.0, 0.0], [lines, LINE_DIST, 1.0, 0.0], [emitters, EMITTER_DIST, 0.65, -100.0]]:
		var m = pair[0]
		if m == null:
			continue
		var p: Transform = m.get_pivot()
		m.pivot_to(cf(Vector3(fmod(timer * pair[2], pair[1]) + pair[3], p.origin.y, p.origin.z)))
	timer += dt * get_scroll_speed() * 3

func space_hit(col):
	tween(group_obj("pink"), {"Color": col}, 0.15)
	tween(em_box, {"Value": col}, 0.15)
