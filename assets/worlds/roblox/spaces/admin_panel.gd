extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Admin Panel" (AdminPanel): a glitchy hacker console. On
# every hit the neon takes the note colour, a random group of error words
# flashes up shaking, and a new error line prints on the console in the note colour.

var stuff = []
var shaking = [] # [part, start cframe]
var neon_words = [] # word / sign parts that are also neon
var p1
var p2
var console
var commands_rect = []
var words = []
var lines = [] # [node, born]
var order = 0

func _init():
	slug = "admin_panel"

func space_init():
	var w = space_obj.child("Words")
	if w != null:
		for c in w.kids():
			stuff.append(c.kids())
	for g in stuff:
		for p in g:
			p.set_transparency(1)
			if p.rname == "Neon":
				neon_words.append(p)
			if p.is_part():
				shaking.append([p, p.get_cframe()])
	p1 = space_obj.at("Particles/Colored/ParticleEmitter")
	p2 = space_obj.at("Particles/Colored/ParticleEmitter2")
	console = space_obj.at("Console/Console")
	var cmd = space_obj.at("Console/Console/SurfaceGui/commands")
	if cmd != null:
		commands_rect = cmd.data.get("p", {}).get("rect", [])
	var cw = space_obj.child("ConsoleWords")
	if cw != null:
		words = cw.kids()
		cw.visible = false

func space_load():
	group_color("neon", Color(1, 1, 1))

func space_update(dt):
	if rate_limit("admin", 60, dt) <= 0:
		return
	for e in shaking:
		var v = Vector3(rand() * 2 - 1, rand() * 2 - 1, rand() * 2 - 1).normalized() * 0.3
		e[0].set_cframe(moved(e[1], v))

func space_hit(col):
	tween(group_obj("neon"), {"Color": col}, 1.0, "Quint", "Out")
	for p in neon_words:
		tween(p, {"Color": col}, 1.0, "Quint", "Out")
	if not stuff.empty():
		for p in stuff[rand_int(0, stuff.size() - 1)]:
			p.set_transparency(-1)
			tween(p, {"Transparency": 1.0}, 1.0, "Quint", "Out")
	for e in [p1, p2]:
		if e != null:
			e.set_emitter_color(col)
	_print_line(col)

# a new error line at the bottom of the console; old lines scroll up and expire after 5 s
func _print_line(col: Color):
	if console == null or words.empty() or commands_rect.size() < 11:
		return
	var w = words[rand_int(0, words.size() - 1)].clone_obj()
	w.set_color(col)
	console.add_child(w)
	lines.append([w, now()])
	after(5.0, self, "_expire", [w])
	_layout()

func _expire(w):
	for i in range(lines.size()):
		if lines[i][0] == w:
			lines.remove(i)
			break
	if is_instance_valid(w):
		w.destroy()
	_layout()

func _layout():
	var r: Array = commands_rect
	var c = Vector3(r[0], r[1], r[2])
	var u = Vector3(r[3], r[4], r[5])
	var v = Vector3(r[6], r[7], r[8])
	var w: float = r[9]
	var h: float = r[10]
	var n = -(u.cross(v)).normalized()
	var lh = h / 14.0
	var fit = int(h / lh)
	var start = max(0, lines.size() - fit)
	for i in range(lines.size()):
		var node = lines[i][0]
		if not is_instance_valid(node):
			continue
		if i < start:
			node.visible = false
			continue
		node.visible = true
		var aspect: float = node.data.get("p", {}).get("aspect", 4.0)
		var ww = min(aspect * lh, w)
		var row = i - start
		var pos = c - u * w / 2 + u * ww / 2 - v * h / 2 + v * lh * (row + 0.5) + n * 0.01
		node.transform = Transform(Basis(u * (ww / aspect), -v * lh, n), pos)
