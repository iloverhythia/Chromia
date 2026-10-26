extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Base for the backgrounds converted from Roblox Rhythia's "Spaces" folder.
#
# A space is stored as assets/worlds/roblox/<slug>/space.json (objects, materials,
# lighting) + space.rgeo (shapes, compressed). This script builds it, sets up the
# lighting/sky/fog/water and runs Roblox-style tweens and timers for the space's
# own script (a subclass in assets/worlds/roblox/spaces/), which overrides:
#   space_init()        SpaceBase.new / _init
#   space_load()        Load / LoadPost
#   space_update(dt)    Update
#   space_hit(col)      OnHit
#   space_miss(col)     OnMiss
#   space_beat()        OnBeat (guessed from the music)
# Everything inside rbx_root uses Roblox coordinates (studs, Roblox axes); the
# root turns them into Chromia's (1/5 scale, Roblox -X = Chromia forward,
# Roblox (0, 3, 0) = the middle of Chromia's grid).

const NodeScript = preload("res://assets/worlds/roblox/rbx_node.gd")
const DIR = "res://assets/worlds/roblox/"
const STUD = 0.2
# Roblox Rhythia's play area is centred 3 studs up; that point sits at Chromia's grid
const CENTER_Y = 3.0
const CAMERA_FAR = 2000.0

var slug = ""
var D = {}
var geo_file: File = null
var rbx_root: Spatial
var folder # the space's folder object
var space_obj # folder/Space
var assets_obj # folder/Assets
var lighting # proxy for game.Lighting properties the scripts change
var env_effects = true
var rng = RandomNumberGenerator.new()
var groups = {}
var sun: DirectionalLight = null

var _mats = {}
var _shaders = {}
var _meshes = {}
var _multimeshes = {}
var _tweens = []
var _timers = []
var _cam: Camera = null
var _cam_far = -1.0
var _beat_avg = 0.0
var _beat_last = 0.0
var _music_bus = 0
var _ready_done = false
var _rate = {}

# ------------------------------------------------------------------ setup
func _build():
	rng.randomize()
	env_effects = space_effects
	if slug == "":
		slug = name.to_lower()
	var f = File.new()
	if f.open(DIR + slug + "/space.json", File.READ) != OK:
		push_error("roblox space missing: " + slug)
		return
	var r = parse_json(f.get_as_text())
	f.close()
	if typeof(r) != TYPE_DICTIONARY:
		push_error("roblox space unreadable: " + slug)
		return
	D = r
	geo_file = File.new()
	if geo_file.open_compressed(DIR + slug + "/space.rgeo", File.READ, File.COMPRESSION_DEFLATE) != OK:
		geo_file = null
	for g in D.get("groups", {}).keys():
		var gd: Dictionary = D.groups[g]
		groups[g] = {"kind": gd.get("kind", "part"), "s": gd.get("s", 1.0), "v": gd.get("v", 1.0), "mats": [], "color": null,
			"c0": _col(gd.get("c0", [1, 1, 1]))}
	rbx_root = Spatial.new()
	rbx_root.name = "RobloxSpace"
	rbx_root.transform = Transform(Basis(Vector3(0, 0, STUD), Vector3(0, STUD, 0), Vector3(-STUD, 0, 0)), Vector3(0, -CENTER_Y * STUD, 0))
	add_child(rbx_root)
	_setup_environment()
	folder = build_node(D.root, rbx_root)
	space_obj = folder.child("Space")
	assets_obj = folder.child("Assets")
	if assets_obj != null:
		assets_obj.visible = false
	lighting = LightingProxy.new(self)
	var game = get_parent().get_node_or_null("Game") if get_parent() != null else null
	if game != null and game.has_signal("miss") and not game.is_connected("miss", self, "_on_game_miss"):
		game.connect("miss", self, "_on_game_miss")
	var mb = AudioServer.get_bus_index("Music")
	_music_bus = mb if mb >= 0 else 0
	_cam = get_viewport().get_camera() if get_viewport() != null else null
	if _cam != null:
		_cam_far = _cam.far
		_cam.far = max(_cam.far, CAMERA_FAR * STUD * 1.5)
	space_init()
	space_load()
	_ready_done = true

func _exit_tree():
	if _cam != null and is_instance_valid(_cam) and _cam_far > 0:
		_cam.far = _cam_far

func _tick(dt):
	if not _ready_done:
		return
	_run_timers(dt)
	_run_tweens(dt)
	_detect_beat(dt)
	space_update(dt)
	_update_trails(dt)

# ------------------------------------------------------------------ trails
var _trails = []

func _update_trails(dt: float):
	if _trails.empty():
		return
	var live = []
	for tr in _trails:
		var n = tr.node
		if not is_instance_valid(n) or not n.is_inside_tree():
			# the object is gone: its trail goes with it
			if is_instance_valid(tr.ig):
				tr.ig.queue_free()
			continue
		live.append(tr)
		if not n.is_visible_in_tree():
			tr.ig.clear()
			tr.pts.clear()
			continue
		var part = n.get_parent()
		if part == null or not part.has_method("get_cframe"):
			continue
		var t: Transform = part.get_cframe()
		var a = t.xform(tr.a0)
		var b = t.xform(tr.a1)
		var pts: Array = tr.pts
		for q in pts:
			q[2] += dt
		pts.push_front([a, b, 0.0])
		while pts.size() > 2 and pts[pts.size() - 1][2] > tr.life:
			pts.pop_back()
		var ig: ImmediateGeometry = tr.ig
		ig.clear()
		if pts.size() < 2 or not n.enabled:
			continue
		ig.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for q in pts:
			var k: float = clamp(q[2] / tr.life, 0.0, 1.0)
			var c: Color = tr.color
			c.a *= clamp(1.0 - _seq_at(tr.trseq, k, 1), 0.0, 1.0)
			ig.set_color(c)
			ig.set_uv(Vector2(k, 0))
			ig.add_vertex(q[0])
			ig.set_color(c)
			ig.set_uv(Vector2(k, 1))
			ig.add_vertex(q[1])
		ig.end()
	_trails = live

func _build_trail(n, p: Dictionary):
	if not (p.has("a0") and p.has("a1")):
		return
	var ig = ImmediateGeometry.new()
	ig.name = "_trail"
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.vertex_color_use_as_albedo = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	if float(p.get("LightEmission", 0.0)) > 0.4:
		m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	var t: String = p.get("Texture", "")
	if t != "":
		var tx = load(t)
		if tx != null:
			m.albedo_texture = tx
	ig.material_override = m
	ig.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	rbx_root.add_child(ig)
	var colseq: Array = p.get("Color", [[0, 1, 1, 1, 0]])
	var a0 = _x12(p.a0)
	var a1 = _x12(p.a1)
	_trails.append({"node": n, "ig": ig, "a0": a0.origin, "a1": a1.origin, "pts": [], "life": max(0.05, float(p.get("Lifetime", 1.0))),
		"color": Color(_seq_at(colseq, 0.0, 1), _seq_at(colseq, 0.0, 2), _seq_at(colseq, 0.0, 3)), "trseq": p.get("Transparency", [[0, 0, 0], [1, 1, 0]])})
	n.enabled = p.get("Enabled", true)
	n.extra["trail_ig"] = ig

func set_trail_color(n, c: Color):
	for tr in _trails:
		if tr.node == n:
			tr.color = c

# ------------------------------------------------------------------ selection box
func _build_selbox(n, p: Dictionary):
	if not p.has("box"):
		return
	var b = _v3(p.box) / 2.0
	var th = float(p.get("thick", 0.15))
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners = []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				corners.append(Vector3(x * b.x, y * b.y, z * b.z))
	var cube = CubeMesh.new()
	var edges = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var mi = MultiMeshInstance.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	cube.size = Vector3.ONE
	mm.mesh = cube
	mm.instance_count = edges.size()
	for i in range(edges.size()):
		var a: Vector3 = corners[edges[i][0]]
		var c: Vector3 = corners[edges[i][1]]
		var d = c - a
		var sc = Vector3(max(abs(d.x), th), max(abs(d.y), th), max(abs(d.z), th))
		mm.set_instance_transform(i, Transform(Basis().scaled(sc), (a + c) / 2.0))
	mi.multimesh = mm
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = n.color
	mi.material_override = m
	n.extra["selbox_mat"] = m
	n.add_child(mi)

func set_selbox_color(n, c: Color):
	if n.extra.has("selbox_mat"):
		n.extra.selbox_mat.albedo_color = c

# loose TextLabel (not on a SurfaceGui): a quad 1 stud high the script places itself
func _build_text(n, p: Dictionary):
	if p.get("tex", "") == "":
		return
	var q = QuadMesh.new()
	q.size = Vector2(float(p.get("aspect", 4.0)), 1.0)
	var mi = MeshInstance.new()
	mi.mesh = q
	var m = _make_mat({"shade": "gui", "blend": "mix", "cull": "none", "tex": p.tex, "texmode": 2})
	mi.material_override = m
	n.mats.append(m)
	if n.geo == null:
		n.geo = Spatial.new()
		n.geo.name = "_geo"
		n.add_child(n.geo)
	n.geo.add_child(mi)

func _on_hit(col: Color):
	if _ready_done:
		space_hit(col)

func _on_game_miss(col):
	if _ready_done:
		space_miss(col if col is Color else Color(1, 0, 0))

# --- overridables
func space_init():
	pass
func space_load():
	pass
func space_update(_dt: float):
	pass
func space_hit(_col: Color):
	pass
func space_miss(_col: Color):
	pass
func space_beat():
	pass

# ------------------------------------------------------------------ Roblox-ish helpers
func get_color() -> Color:
	return last_hit_color

func get_speed() -> float:
	if Rhythia.has_method("current_speed_multiplier"):
		return float(Rhythia.current_speed_multiplier())
	return 1.0

func get_scroll_speed() -> float:
	return approach_rate / 50.0 * get_speed()

func is_paused() -> bool:
	return false

func now() -> float:
	return OS.get_ticks_msec() / 1000.0

# music loudness on Roblox's PlaybackLoudness scale (0 .. ~1000)
func loudness() -> float:
	var db = max(AudioServer.get_bus_peak_volume_left_db(_music_bus, 0), AudioServer.get_bus_peak_volume_right_db(_music_bus, 0))
	return clamp(db2linear(db), 0.0, 1.5) * 700.0

# RateLimit:Run(script, fps): returns the time passed when it is time to run, else 0
func rate_limit(key: String, fps: float, dt: float) -> float:
	var acc: float = _rate.get(key, 0.0) + dt
	if acc < 1.0 / fps:
		_rate[key] = acc
		return 0.0
	_rate[key] = 0.0
	return acc

func camera_pos() -> Vector3:
	var c = get_viewport().get_camera() if get_viewport() != null else null
	if c == null:
		return Vector3(17.5, CENTER_Y, 0)
	return rbx_root.global_transform.affine_inverse().xform(c.global_transform.origin)

func angles(x: float, y: float, z: float) -> Basis:
	return Basis(Vector3(1, 0, 0), x) * Basis(Vector3(0, 1, 0), y) * Basis(Vector3(0, 0, 1), z)

func cfa(x: float, y: float, z: float) -> Transform:
	return Transform(angles(x, y, z), Vector3())

func cf(p: Vector3) -> Transform:
	return Transform(Basis(), p)

func cf_look(p: Vector3, at: Vector3) -> Transform:
	if p.is_equal_approx(at):
		return cf(p)
	var up = Vector3.UP
	if abs((at - p).normalized().dot(up)) > 0.999:
		up = Vector3.BACK
	return Transform(Basis(), p).looking_at(at, up)

func moved(t: Transform, v: Vector3) -> Transform:
	t.origin += v
	return t

func rot_only(t: Transform) -> Transform:
	t.origin = Vector3()
	return t

func look_vector(t: Transform) -> Vector3:
	return -t.basis.z

func up_vector(t: Transform) -> Vector3:
	return t.basis.y

func rand() -> float:
	return rng.randf()

func rand_int(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func pick(arr: Array):
	if arr.empty():
		return null
	return arr[rng.randi() % arr.size()]

func lerp_color(a: Color, b: Color, t: float) -> Color:
	return a.linear_interpolate(b, t)

func from_hsv(h: float, s: float, v: float) -> Color:
	return Color.from_hsv(fposmod(h, 1.0), clamp(s, 0, 1), clamp(v, 0, 1))

func rmod(a: float, b: float) -> float:
	# Lua-style Mod used by the space scripts: sign(a) * (|a| % |b|)
	return sign(a) * fmod(abs(a), abs(b))

# all objects below `o` that are of class c (BasePart = any part)
func find_all(o, c: String) -> Array:
	var out = []
	if o == null:
		return out
	for d in o.desc():
		if d.is_a(c):
			out.append(d)
	return out

# a model's PrimaryPart
func primary(model):
	if model == null:
		return null
	var n: String = model.data.get("p", {}).get("primary", "")
	if n == "":
		return null
	for d in model.desc():
		if d.rname == n and d.is_part():
			return d
	return null

func named(o, n: String) -> Array:
	var out = []
	if o == null:
		return out
	for d in o.desc():
		if d.rname == n:
			out.append(d)
	return out

# ------------------------------------------------------------------ groups
# A group is a set of merged objects that one script line recolours at once.
func group_color(g: String, c: Color):
	if not groups.has(g):
		return
	var gr: Dictionary = groups[g]
	gr.color = c
	for m in gr.mats:
		if gr.kind in ["part", "hsv"]:
			m.set_shader_param("over", Color(c.r, c.g, c.b, 1.0))
		else:
			m.set_shader_param("tint", Color(c.r, c.g, c.b, 1.0))

func group_get(g: String) -> Color:
	if groups.has(g):
		return groups[g].color if groups[g].color != null else groups[g].c0
	return Color(1, 1, 1)

var _gproxies = {}
# something tween() can animate: tween(group_obj("neon"), {"Color": c}, 0.15)
func group_obj(g: String):
	if not _gproxies.has(g):
		_gproxies[g] = GroupProxy.new(self, g)
	return _gproxies[g]

# a number / colour that calls target.method(value) whenever it changes (Roblox
# NumberValue + GetPropertyChangedSignal); tween its "Value"
func value_box(start, target: Object, method: String):
	return ValueBox.new(start, target, method)

class ValueBox:
	extends Reference
	var value
	var t: Object
	var m: String
	func _init(v, target, method):
		value = v
		t = target
		m = method
	func get_prop(_p):
		return value
	func set_prop(_p, v):
		value = v
		if is_instance_valid(t):
			t.call(m, v)

class GroupProxy:
	extends Reference
	var sp
	var g: String
	func _init(s, n):
		sp = s
		g = n
	func get_prop(_p):
		return sp.group_get(g)
	func set_prop(_p, v):
		sp.group_color(g, v)

class LightingProxy:
	extends Reference
	var sp
	func _init(s):
		sp = s
	func get_prop(p):
		if p == "FogColor" and sp.env != null:
			return sp.env.fog_color
		return null
	func set_prop(p, v):
		if p == "FogColor" and sp.env != null:
			sp.env.fog_color = v
			if sp.env.background_mode == Environment.BG_COLOR:
				sp.env.background_color = v

# ------------------------------------------------------------------ tweens
# Roblox TweenService: tween(obj, {"Color": c, "Transparency": 1}, time, "Quint", "Out")
func tween(obj, props: Dictionary, time: float, style := "Linear", dir := "Out", repeat := 0, reverses := false, delay := 0.0) -> Dictionary:
	var tw = {"obj": obj, "props": {}, "time": max(time, 0.0001), "t": 0.0, "style": style, "dir": dir,
		"repeat": repeat, "reverses": reverses, "delay": delay, "done": [], "alive": true, "loops": 0, "paused": false}
	for p in props.keys():
		# a newer tween takes the property over (Roblox cancels the old one)
		for o in _tweens:
			if o.alive and o.obj == obj and o.props.has(p):
				o.props.erase(p)
				if o.props.empty():
					_finish(o)
		tw.props[p] = [obj.get_prop(p), props[p]]
	_tweens.append(tw)
	return tw

# call target.method(binds...) when the tween ends
func on_done(tw: Dictionary, target: Object, method: String, binds := []):
	tw.done.append([target, method, binds])
	return tw

func cancel(tw: Dictionary):
	tw.alive = false

func _finish(tw: Dictionary):
	if not tw.alive:
		return
	tw.alive = false
	for d in tw.done:
		if is_instance_valid(d[0]):
			d[0].callv(d[1], d[2])

func _run_tweens(dt: float):
	if _tweens.empty():
		return
	var live = []
	for tw in _tweens.duplicate():
		if not tw.alive:
			continue
		var o = tw.obj
		if typeof(o) == TYPE_OBJECT and not is_instance_valid(o):
			tw.alive = false
			continue
		if tw.paused:
			live.append(tw)
			continue
		tw.t += dt
		var a: float = (tw.t - tw.delay) / tw.time
		if a < 0.0:
			live.append(tw)
			continue
		var ended = false
		var cycles = 2 if tw.reverses else 1
		var span = float(cycles)
		var k = a
		if tw.repeat < 0 or tw.loops < tw.repeat:
			if a >= span:
				tw.loops += 1
				tw.t -= tw.time * span
				k = a - span
		elif a >= span:
			k = span
			ended = true
		var e = 0.0
		if tw.reverses:
			e = k if k <= 1.0 else 2.0 - k
		else:
			e = min(k, 1.0)
		e = ease_value(tw.style, tw.dir, clamp(e, 0.0, 1.0))
		for p in tw.props.keys():
			var fr = tw.props[p][0]
			var to = tw.props[p][1]
			o.set_prop(p, _mix(fr, to, e))
		if ended:
			_finish(tw)
		elif tw.alive:
			live.append(tw)
	for tw in _tweens:
		if tw.alive and not live.has(tw) and tw.t == 0.0:
			live.append(tw)
	_tweens = live

func _mix(a, b, t: float):
	if a == null:
		return b
	match typeof(b):
		TYPE_REAL, TYPE_INT:
			return lerp(float(a), float(b), t)
		TYPE_COLOR:
			return a.linear_interpolate(b, t)
		TYPE_VECTOR3:
			return a.linear_interpolate(b, t)
		TYPE_TRANSFORM:
			return a.interpolate_with(b, t)
	return b if t >= 1.0 else a

static func _ease_in(style: String, a: float) -> float:
	match style:
		"Linear": return a
		"Sine": return 1.0 - cos(a * PI / 2.0)
		"Quad": return a * a
		"Cubic": return a * a * a
		"Quart": return a * a * a * a
		"Quint": return a * a * a * a * a
		"Exponential": return 0.0 if a <= 0.0 else pow(2.0, 10.0 * (a - 1.0))
		"Circular": return 1.0 - sqrt(max(0.0, 1.0 - a * a))
		"Back":
			var c1 = 1.70158
			return (c1 + 1.0) * a * a * a - c1 * a * a
		"Elastic":
			if a <= 0.0 or a >= 1.0:
				return a
			return -pow(2.0, 10.0 * a - 10.0) * sin((a * 10.0 - 10.75) * (2.0 * PI / 3.0))
		"Bounce":
			return 1.0 - _bounce_out(1.0 - a)
	return a

static func _bounce_out(a: float) -> float:
	var n1 = 7.5625
	var d1 = 2.75
	if a < 1.0 / d1:
		return n1 * a * a
	elif a < 2.0 / d1:
		a -= 1.5 / d1
		return n1 * a * a + 0.75
	elif a < 2.5 / d1:
		a -= 2.25 / d1
		return n1 * a * a + 0.9375
	a -= 2.625 / d1
	return n1 * a * a + 0.984375

static func ease_value(style: String, dir: String, a: float) -> float:
	if dir == "In":
		return _ease_in(style, a)
	if dir == "InOut":
		return _ease_in(style, a * 2.0) / 2.0 if a < 0.5 else 1.0 - _ease_in(style, 2.0 - a * 2.0) / 2.0
	return 1.0 - _ease_in(style, 1.0 - a)

# ------------------------------------------------------------------ timers
# after(0.5, self, "_spawn", [x])  ==  task.delay
func after(t: float, target: Object, method: String, binds := []):
	_timers.append([t, target, method, binds])

func _run_timers(dt: float):
	if _timers.empty():
		return
	var due = []
	var keep = []
	for tm in _timers:
		tm[0] -= dt
		if tm[0] <= 0.0:
			due.append(tm)
		else:
			keep.append(tm)
	_timers = keep
	for tm in due:
		if is_instance_valid(tm[1]):
			tm[1].callv(tm[2], tm[3])

# OnBeat: a simple guess from music peaks (Chromia maps have no beat info)
func _detect_beat(dt: float):
	var l = loudness()
	_beat_avg = lerp(_beat_avg, l, min(1.0, dt * 2.0))
	_beat_last += dt
	if l > _beat_avg * 1.35 + 20.0 and _beat_last > 0.3:
		_beat_last = 0.0
		space_beat()

# ------------------------------------------------------------------ geometry
func _read_mesh(off: int) -> ArrayMesh:
	if _meshes.has(off):
		return _meshes[off]
	var m = ArrayMesh.new()
	if geo_file != null:
		geo_file.seek(off)
		var pos = geo_file.get_var()
		var nrm = geo_file.get_var()
		var uv = geo_file.get_var()
		var col = geo_file.get_var()
		var idx = geo_file.get_var()
		if pos is PoolVector3Array and pos.size() > 0:
			var arr = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = pos
			arr[Mesh.ARRAY_NORMAL] = nrm
			if uv is PoolVector2Array and uv.size() == pos.size():
				arr[Mesh.ARRAY_TEX_UV] = uv
			if col is PoolColorArray and col.size() == pos.size():
				arr[Mesh.ARRAY_COLOR] = col
			arr[Mesh.ARRAY_INDEX] = idx
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[off] = m
	return m

func _read_multimesh(gi: int, off: int) -> MultiMesh:
	var key = "%d:%d" % [gi, off]
	if _multimeshes.has(key):
		return _multimeshes[key]
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	mm.mesh = _read_mesh(int(D.geoms[gi]))
	if geo_file != null:
		geo_file.seek(off)
		var xf = geo_file.get_var()
		var cols = geo_file.get_var()
		mm.instance_count = xf.size() / 4
		mm.transform_array = xf
		mm.color_array = cols
	_multimeshes[key] = mm
	return mm

static func _x12(a: Array) -> Transform:
	return Transform(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11]))

static func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])

static func _col(a) -> Color:
	if typeof(a) != TYPE_ARRAY or a.size() < 3 or a[0] == null:
		return Color(1, 1, 1)
	return Color(float(a[0]), float(a[1]), float(a[2]))

static func num(v, d: float) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_REAL] else d

# ------------------------------------------------------------------ materials
const SHADER = """shader_type spatial;
render_mode MODES;
uniform sampler2D tex : hint_albedo;
uniform float has_tex = 0.0;
uniform float tex_mode = 0.0;
uniform vec4 tint : hint_color = vec4(1.0);
uniform vec4 over : hint_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float alpha = 1.0;
uniform float glow = 1.0;
uniform vec2 uv_off = vec2(0.0);
uniform float shine = 0.0;
void fragment() {
	vec3 c = mix(COLOR.rgb, over.rgb, over.a) * tint.rgb;
	float a = COLOR.a * alpha;
	if (has_tex > 0.5) {
		vec4 t = texture(tex, UV + uv_off);
		if (tex_mode < 1.5) {
			// a model's own texture: see-through texels are cut out
			c = t.rgb * mix(vec3(1.0), tint.rgb, over.a);
			if (t.a < 0.5) { discard; }
		} else { c *= t.rgb; a *= t.a; }
	}
	ALBEDO = c * glow;
	ROUGHNESS = 0.9 - shine * 0.6;
	SPECULAR = 0.2 + shine * 0.5;
	//ALPHA = clamp(a, 0.0, 1.0);
}
"""

func _shader(shade: String, blend: String, cull: String) -> Shader:
	var key = shade + "|" + blend + "|" + cull
	if _shaders.has(key):
		return _shaders[key]
	var modes = []
	if shade in ["neon", "ff", "gui"]:
		modes.append("unshaded")
	if blend == "add":
		modes.append("blend_add")
	elif blend == "mix":
		modes.append("blend_mix")
	modes.append("cull_disabled" if cull == "none" else "cull_back")
	if blend != "opaque":
		modes.append("depth_draw_opaque")
	var code = SHADER.replace("MODES", PoolStringArray(modes).join(", "))
	if blend != "opaque":
		code = code.replace("//ALPHA", "ALPHA")
	var s = Shader.new()
	s.code = code
	_shaders[key] = s
	return s

func _make_mat(def: Dictionary, blend_override := "") -> ShaderMaterial:
	var blend: String = blend_override if blend_override != "" else def.get("blend", "opaque")
	var m = ShaderMaterial.new()
	m.shader = _shader(def.get("shade", "lit"), blend, def.get("cull", "back"))
	m.set_meta("def", def)
	m.set_meta("blend", blend)
	var t: String = def.get("tex", "")
	if t != "":
		var tx = load(t)
		if tx != null:
			m.set_shader_param("tex", tx)
			m.set_shader_param("has_tex", 1.0)
			m.set_shader_param("tex_mode", float(def.get("texmode", 2)))
	if def.get("shade", "") == "neon":
		m.set_shader_param("glow", 1.25)
	if def.get("glass", 0):
		m.set_shader_param("shine", 1.0)
	if def.get("shade", "") == "ff":
		m.set_shader_param("alpha", 0.6)
	return m

# shared material number `mi` (or a private copy the object can recolour)
func material(mi: int, own := false) -> ShaderMaterial:
	var defs: Array = D.mats
	var def: Dictionary = defs[mi]
	if own:
		return _make_mat(def)
	if _mats.has(mi):
		return _mats[mi]
	var m = _make_mat(def)
	_mats[mi] = m
	var g: String = def.get("group", "")
	if g != "" and groups.has(g):
		groups[g].mats.append(m)
	return m

# colour / transparency of an object's own material; switches to a see-through
# version of the shader when needed
func set_mat_look(m: ShaderMaterial, c: Color, tr: float, is_part: bool):
	var def: Dictionary = m.get_meta("def")
	if tr > 0.001 and m.get_meta("blend") == "opaque":
		m.shader = _shader(def.get("shade", "lit"), "mix", def.get("cull", "back"))
		m.set_meta("blend", "mix")
	m.set_shader_param("tint", Color(max(c.r, 0.0), max(c.g, 0.0), max(c.b, 0.0), 1.0))
	var a = clamp(1.0 - tr, 0.0, 1.0)
	if def.get("shade", "") == "ff":
		a *= 0.6
	m.set_shader_param("alpha", a)
	var boost = 1.0 + max(0.0, -tr) * 0.5
	m.set_shader_param("glow", boost * (1.25 if def.get("shade", "") == "neon" else 1.0))

# ------------------------------------------------------------------ objects
const LOOK_CLASSES = ["Decal", "Texture", "ImageLabel", "ImageButton", "TextLabel", "Frame"]

func build_node(d: Dictionary, parent: Node):
	var n = Spatial.new()
	n.set_script(NodeScript)
	n.space = self
	n.rclass = d.get("c", "Folder")
	n.rname = d.get("n", "")
	n.data = d
	n.name = _safe_name(n.rname)
	if d.has("x"):
		n.transform = _x12(d.x)
	var p: Dictionary = d.get("p", {})
	if p.has("size"):
		n.size = _v3(p.size)
		n.base_size = n.size
	if p.has("color"):
		n.color = _col(p.color)
	if n.rclass in ["PointLight", "SpotLight", "SurfaceLight"] and typeof(p.get("Color")) == TYPE_ARRAY:
		n.color = _col(p.Color)
	n.transparency = p.get("tr", 0.0)
	n.material_id = p.get("mat", 256)
	n.tinted = p.get("tint", true)
	if p.has("value"):
		var v = p.value
		if n.rclass == "Color3Value" and typeof(v) == TYPE_ARRAY:
			v = _col(v)
		elif n.rclass == "Vector3Value" and typeof(v) == TYPE_ARRAY:
			v = _v3(v)
		elif n.rclass == "CFrameValue" and typeof(v) == TYPE_ARRAY:
			v = _x12(v)
		n.value = v
	if p.get("hidden", false):
		n.visible = false
	if parent != null:
		parent.add_child(n)
	# pictures merged onto a part keep their own look; a part's colour and
	# transparency only apply to the part's shape ("m")
	var own: bool = n.rclass in LOOK_CLASSES
	# shapes
	if d.has("m") or d.has("g") or d.has("mm"):
		n.geo = Spatial.new()
		n.geo.name = "_geo"
		n.add_child(n.geo)
	if d.has("m"):
		var mi = MeshInstance.new()
		mi.mesh = _read_mesh(int(D.geoms[int(d.m[0])]))
		mi.transform = _x12(d.m[2])
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var mat = material(int(d.m[1]), true)
		mi.material_override = mat
		n.mats.append(mat)
		n.part_mesh = mi
		n.geo.add_child(mi)
	for s in d.get("g", []):
		var mi2 = MeshInstance.new()
		mi2.mesh = _read_mesh(int(s[1]))
		mi2.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var mat2 = material(int(s[0]), own)
		if own:
			n.mats.append(mat2)
		mi2.material_override = mat2
		n.geo.add_child(mi2)
	for s in d.get("mm", []):
		var mmi = MultiMeshInstance.new()
		mmi.multimesh = _read_multimesh(int(s[0]), int(s[2]))
		mmi.material_override = material(int(s[1]))
		mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		n.geo.add_child(mmi)
	match n.rclass:
		"ParticleEmitter":
			_build_emitter(n, p)
		"PointLight", "SpotLight", "SurfaceLight":
			_build_light(n, p)
		"Beam":
			_build_beam(n, p)
		"Trail":
			_build_trail(n, p)
		"SelectionBox":
			_build_selbox(n, p)
		"TextLabel":
			if not d.has("g"):
				_build_text(n, p)
	if n.mats.size() > 0 or n.is_part():
		n._apply_look()
	for k in d.get("k", []):
		build_node(k, n)
	return n

func _safe_name(s: String) -> String:
	var o = s.replace("/", "_").replace(":", "_").replace(".", "_").replace("@", "_").replace("\"", "_").replace("%", "_")
	return o if o != "" else "_"

func clone_node(src):
	var c = build_node(src.data, null)
	c.transform = src.get_cframe()
	c.size = src.size
	if src.size != src.base_size:
		c.set_size(src.size)
	c.color = src.color
	c.transparency = src.transparency
	c.value = src.value
	c.extra = src.extra.duplicate()
	c.extra.erase("on_value")
	c._apply_look()
	return c

func forget(n):
	for tw in _tweens:
		if tw.obj == n:
			tw.alive = false

# ------------------------------------------------------------------ particles
static func _seq_at(seq: Array, t: float, idx: int) -> float:
	# NumberSequence [[time, value, envelope]...] / ColorSequence [[time, r, g, b, env]...]
	if seq.empty():
		return 0.0
	if t <= seq[0][0]:
		return seq[0][idx]
	for i in range(1, seq.size()):
		if t <= seq[i][0]:
			var a = seq[i - 1]
			var b = seq[i]
			var k = 0.0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
			return lerp(a[idx], b[idx], k)
	return seq[seq.size() - 1][idx]

func _emitter_gradient(colseq: Array, trseq: Array) -> Gradient:
	var times = {}
	for k in colseq:
		times[float(k[0])] = true
	for k in trseq:
		times[float(k[0])] = true
	var ts = times.keys()
	ts.sort()
	var g = Gradient.new()
	var offs = PoolRealArray()
	var cols = PoolColorArray()
	for t in ts:
		var c = Color(_seq_at(colseq, t, 1), _seq_at(colseq, t, 2), _seq_at(colseq, t, 3)) if not colseq.empty() else Color(1, 1, 1)
		c.a = clamp(1.0 - (_seq_at(trseq, t, 1) if not trseq.empty() else 0.0), 0.0, 1.0)
		offs.append(t)
		cols.append(c)
	if offs.size() < 2:
		offs = PoolRealArray([0.0, 1.0])
		var c0 = cols[0] if cols.size() > 0 else Color(1, 1, 1)
		cols = PoolColorArray([c0, c0])
	g.offsets = offs
	g.colors = cols
	return g

func _build_emitter(n, p: Dictionary):
	var e = CPUParticles.new()
	e.name = "_emitter"
	var rate: float = p.get("Rate", 20.0)
	var life: Array = p.get("Lifetime", [1.0, 1.0])
	var lmax = max(0.05, float(life[1]))
	e.lifetime = lmax
	e.lifetime_randomness = clamp(1.0 - float(life[0]) / lmax, 0.0, 1.0)
	e.amount = int(clamp(ceil(rate * lmax) + 1, 1, 600))
	if rate <= 0.0:
		e.amount = 1
	e.emitting = p.get("Enabled", true) and rate > 0.0
	e.local_coords = true
	var sp: Array = p.get("Speed", [5.0, 5.0])
	e.initial_velocity = float(sp[1])
	e.initial_velocity_random = clamp(1.0 - float(sp[0]) / max(0.001, float(sp[1])), 0.0, 1.0)
	var dirs = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)]
	e.direction = dirs[clamp(int(p.get("EmissionDirection", 1)), 0, 5)]
	var spread: Array = p.get("SpreadAngle", [0.0, 0.0])
	e.spread = clamp(max(abs(spread[0]), abs(spread[1])), 0.0, 180.0)
	var acc = _v3(p.get("Acceleration", [0, 0, 0]))
	# Acceleration is in world space; the emitter works in its part's space
	e.gravity = n.get_parent().get_cframe().basis.inverse().xform(acc) if n.get_parent() != null and n.get_parent().has_method("get_cframe") else acc
	e.damping = clamp(float(p.get("Drag", 0.0)) * float(sp[1]) * 0.5, 0.0, 100.0)
	var rot: Array = p.get("Rotation", [0.0, 0.0])
	e.angle = float(rot[1])
	e.angle_random = 1.0 if rot[0] != rot[1] else 0.0
	var rs: Array = p.get("RotSpeed", [0.0, 0.0])
	e.angular_velocity = float(rs[1])
	e.angular_velocity_random = 1.0 if rs[0] != rs[1] else 0.0
	e.speed_scale = float(p.get("TimeScale", 1.0))
	var box = _v3(p.get("box", [0, 0, 0]))
	if box.length() > 0.001:
		e.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
		e.emission_box_extents = box / 2
	# size over life
	var sseq: Array = p.get("Size", [[0, 1, 0], [1, 1, 0]])
	var smax = 0.001
	for k in sseq:
		smax = max(smax, float(k[1]) + float(k[2]))
	e.scale_amount = smax
	var cv = Curve.new()
	cv.max_value = 1.0
	for k in sseq:
		cv.add_point(Vector2(float(k[0]), clamp(float(k[1]) / smax, 0.0, 1.0)))
	e.scale_amount_curve = cv
	var colseq: Array = p.get("Color", [[0, 1, 1, 1, 0], [1, 1, 1, 1, 0]])
	var trseq: Array = p.get("Transparency", [[0, 0, 0], [1, 0, 0]])
	n.extra["tr_seq"] = trseq
	e.color_ramp = _emitter_gradient(colseq, trseq)
	var q = QuadMesh.new()
	q.size = Vector2(1, 1)
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.vertex_color_use_as_albedo = true
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	if float(p.get("LightEmission", 0.0)) > 0.4:
		m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	var t: String = p.get("Texture", "")
	if t != "":
		var tx = load(t)
		if tx != null:
			m.albedo_texture = tx
	var br = float(p.get("Brightness", 1.0))
	m.albedo_color = Color(br, br, br, 1.0) if br <= 1.0 else Color(1, 1, 1, 1)
	if br > 1.0:
		m.emission_enabled = false
	q.material = m
	e.mesh = q
	n.emitter = e
	n.enabled = e.emitting
	n.add_child(e)
	if not env_effects and false:
		e.emitting = false

func recolor_emitter(n, c1: Color, c2: Color):
	if n.emitter == null:
		return
	var trseq: Array = n.extra.get("tr_seq", [])
	n.emitter.color_ramp = _emitter_gradient([[0, c1.r, c1.g, c1.b, 0], [1, c2.r, c2.g, c2.b, 0]], trseq)

# ParticleEmitter:Emit(count)
func burst(n, count: int):
	var e: CPUParticles = n.emitter
	var b: CPUParticles = e.duplicate()
	b.amount = int(clamp(count, 1, 300))
	b.one_shot = true
	b.explosiveness = 1.0
	b.emitting = true
	n.add_child(b)
	after(b.lifetime / max(0.01, b.speed_scale) + 0.2, b, "queue_free")

# ------------------------------------------------------------------ lights & beams
func _build_light(n, p: Dictionary):
	if Rhythia.get("dev") == "mobile":
		return
	var range_ = float(p.get("Range", 8.0))
	var br = float(p.get("Brightness", 1.0))
	var l: Light
	if n.rclass == "PointLight":
		var o = OmniLight.new()
		o.omni_range = range_ * STUD
		o.omni_attenuation = 1.0
		l = o
	else:
		var s = SpotLight.new()
		s.spot_range = range_ * STUD
		s.spot_angle = clamp(float(p.get("Angle", 90.0)) / 2.0, 1.0, 89.0)
		var faces = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)]
		var dir: Vector3 = faces[clamp(int(p.get("Face", 5)), 0, 5)]
		var up = Vector3.UP if abs(dir.y) < 0.9 else Vector3.BACK
		s.transform = Transform(Basis(), Vector3()).looking_at(dir, up)
		l = s
	l.light_color = n.color
	l.light_energy = clamp(br * 0.5, 0.0, 8.0)
	l.shadow_enabled = false
	l.visible = p.get("Enabled", true)
	n.enabled = l.visible
	n.light = l
	n.add_child(l)

func _build_beam(n, p: Dictionary):
	if not (p.has("a0") and p.has("a1")):
		return
	var a0 = _x12(p.a0)
	var a1 = _x12(p.a1)
	var w0 = float(p.get("Width0", 1.0))
	var w1 = float(p.get("Width1", 1.0))
	var colseq: Array = p.get("Color", [[0, 1, 1, 1, 0], [1, 1, 1, 1, 0]])
	var trseq: Array = p.get("Transparency", [[0, 0, 0], [1, 0, 0]])
	var segs = 10
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along = a1.origin - a0.origin
	var length = along.length()
	var side: Vector3
	if p.get("FaceCamera", false):
		var to_cam = (camera_pos() - (a0.origin + a1.origin) / 2.0).normalized()
		side = along.cross(to_cam).normalized()
	else:
		side = a0.basis.y.normalized()
	if side.length() < 0.01:
		side = Vector3.UP
	var tl = float(p.get("TextureLength", 1.0))
	var mode = int(p.get("TextureMode", 0))
	for i in range(segs + 1):
		var t = float(i) / segs
		var pos = a0.origin.linear_interpolate(a1.origin, t)
		var w: float = lerp(w0, w1, t)
		var c = Color(_seq_at(colseq, t, 1), _seq_at(colseq, t, 2), _seq_at(colseq, t, 3), clamp(1.0 - _seq_at(trseq, t, 1), 0.0, 1.0))
		var u = t if mode == 0 else t * length / max(0.01, tl)
		st.add_color(c)
		st.add_uv(Vector2(u, 0))
		st.add_vertex(pos + side * w / 2.0)
		st.add_color(c)
		st.add_uv(Vector2(u, 1))
		st.add_vertex(pos - side * w / 2.0)
	for i in range(segs):
		var b = i * 2
		st.add_index(b)
		st.add_index(b + 1)
		st.add_index(b + 2)
		st.add_index(b + 2)
		st.add_index(b + 1)
		st.add_index(b + 3)
	var mi = MeshInstance.new()
	mi.mesh = st.commit()
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.vertex_color_use_as_albedo = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	if float(p.get("LightEmission", 0.0)) > 0.4:
		m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	var t2: String = p.get("Texture", "")
	if t2 != "":
		var tx = load(t2)
		if tx != null:
			m.albedo_texture = tx
	var br = float(p.get("Brightness", 1.0))
	m.albedo_color = Color(min(br, 2.0), min(br, 2.0), min(br, 2.0))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	n.beam = mi
	n.extra["beam_speed"] = float(p.get("TextureSpeed", 0.0))
	n.add_child(mi)
	mi.visible = p.get("Enabled", true)

func set_beam_color(n, c: Color):
	if n.beam == null:
		return
	var m: SpatialMaterial = n.beam.material_override
	m.albedo_color = c

# ------------------------------------------------------------------ lighting
func _setup_environment():
	var L: Dictionary = D.get("lighting", {})
	env.background_mode = Environment.BG_COLOR
	var fog_col = _col(L.get("FogColor", [0, 0, 0]))
	env.background_color = Color(0, 0, 0)
	if D.has("sky"):
		var tx = load(D.sky)
		if tx != null:
			var ps = PanoramaSky.new()
			ps.panorama = tx
			ps.radiance_size = Sky.RADIANCE_SIZE_32
			env.background_mode = Environment.BG_SKY
			env.background_sky = ps
			var rot: Array = D.get("sky_rot", [0, 0, 0])
			env.background_sky_rotation_degrees = Vector3(-rot[2], rot[1], rot[0])
	else:
		env.background_color = fog_col
	var amb = _col(L.get("Ambient", [0.5, 0.5, 0.5]))
	var outdoor = _col(L.get("OutdoorAmbient", [0.5, 0.5, 0.5]))
	env.ambient_light_color = Color(clamp(amb.r + outdoor.r * 0.3, 0, 1), clamp(amb.g + outdoor.g * 0.3, 0, 1), clamp(amb.b + outdoor.b * 0.3, 0, 1))
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 0.0
	var fog_end = num(L.get("FogEnd"), 100000.0)
	if fog_end < 20000.0:
		env.fog_enabled = true
		env.fog_color = fog_col
		env.fog_sun_amount = 0.0
		env.fog_depth_enabled = true
		env.fog_depth_begin = num(L.get("FogStart"), 0.0) * STUD
		env.fog_depth_end = max(env.fog_depth_begin + 1.0, fog_end * STUD)
		env.fog_depth_curve = 1.0
		env.fog_height_enabled = false
	if D.has("atmosphere"):
		var at: Dictionary = D.atmosphere
		var dens = float(at.get("Density", 0.3))
		if dens > 0.01:
			env.fog_enabled = true
			env.fog_color = _col(at.get("Color", [0.5, 0.5, 0.5])).linear_interpolate(_col(at.get("Decay", [0.5, 0.5, 0.5])), 0.5)
			env.fog_depth_enabled = true
			env.fog_depth_begin = 0.0
			env.fog_depth_end = clamp(700.0 / dens, 200.0, 20000.0) * STUD
			env.fog_depth_curve = 0.6
			env.fog_sun_amount = 0.0
	if D.has("cc") and D.cc.get("Enabled", true):
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0 + float(D.cc.get("Brightness", 0.0))
		env.adjustment_contrast = 1.0 + float(D.cc.get("Contrast", 0.0))
		env.adjustment_saturation = 1.0 + float(D.cc.get("Saturation", 0.0))
	# the sun, from the time of day
	var clock = num(L.get("ClockTime"), 14.0)
	var bright = num(L.get("Brightness"), 2.0)
	sun = DirectionalLight.new()
	sun.name = "Sun"
	var a = (clock - 6.0) / 12.0 * PI
	var dir = Vector3(-cos(a), -max(0.15, sin(a)), -0.4).normalized() # Roblox axes: sun travels east (+X) to west
	var up = Vector3.UP if abs(dir.y) < 0.95 else Vector3.BACK
	sun.transform = Transform(Basis(), Vector3()).looking_at(dir, up)
	sun.light_energy = clamp(bright * 0.35, 0.0, 2.0) if sin(a) > -0.1 else clamp(bright * 0.1, 0.0, 0.5)
	sun.shadow_enabled = false
	rbx_root.add_child(sun)
	# water
	var W: Dictionary = D.get("water", {})
	if not W.empty():
		set_meta("water", W)

# a flat water surface over a Roblox Terrain:FillBlock(cf, size, Water)
func add_water(t: Transform, size: Vector3, settings := {}):
	var W: Dictionary = water_settings().duplicate()
	for k in settings.keys():
		W[k] = settings[k]
	var col = _col(W.get("WaterColor", [0.05, 0.33, 0.36])) if typeof(W.get("WaterColor", null)) == TYPE_ARRAY else (W.get("WaterColor") if W.get("WaterColor") is Color else Color(0.05, 0.33, 0.36))
	var tr = float(W.get("WaterTransparency", 0.3))
	var waves = float(W.get("WaterWaveSize", 0.15))
	var speed = float(W.get("WaterWaveSpeed", 10.0))
	var pm = PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	pm.subdivide_width = 64
	pm.subdivide_depth = 64
	var sh = Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec4 col : hint_color;
uniform float alpha = 0.7;
uniform float waves = 0.15;
uniform float speed = 10.0;
void vertex() {
	float w = sin(VERTEX.x * 0.08 + TIME * speed * 0.15) + cos(VERTEX.z * 0.07 + TIME * speed * 0.12);
	VERTEX.y += w * waves * 2.0;
}
void fragment() {
	float n = sin(UV.x * 300.0 + TIME * speed * 0.2) * cos(UV.y * 260.0 - TIME * speed * 0.17);
	NORMAL = normalize(NORMAL + vec3(n * 0.08, 0.0, n * 0.08));
	ALBEDO = col.rgb;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = 0.15;
	SPECULAR = 0.8;
}
"""
	var m = ShaderMaterial.new()
	m.shader = sh
	m.set_shader_param("col", col)
	m.set_shader_param("alpha", clamp(1.0 - tr * 0.8, 0.25, 1.0))
	m.set_shader_param("waves", waves)
	m.set_shader_param("speed", speed)
	var mi = MeshInstance.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var top = t
	top.origin += t.basis.y * size.y / 2.0
	mi.transform = top
	rbx_root.add_child(mi)
	return mi

# Roblox Terrain water settings from the space's WaterSettings folder
func water_settings() -> Dictionary:
	return get_meta("water") if has_meta("water") else {}
