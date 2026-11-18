extends Reference

# The Hand Creator (Settings > VR > Hands): a VR hand you build yourself out
# of parts. Each part is a shape (ball, box, capsule, cylinder, cone, ring,
# crystal) with its own place, turn, size, colour and look (cartoon, shiny,
# glowing, flat), and the whole hand can have an outline, a size, and a
# mirrored or same-shaped left hand.
#
# A design is kept (settings, share codes, what spectators are sent) as a list
# of short lines:
#   "H1;m=1;o=1;oc=14141a;s=100"                      mirror, outline, its colour, size %
#   "sphere;0,0,4;0,0,0;86,40,80;ffffff;toon"         shape; place (mm); turn (degrees); size (mm); colour; look
# and worked on as a Dictionary (parse / encode).
#
# The hand is the right one, in metres with the controller at the origin,
# palm facing -Y, fingers along -Z, the thumb on the -X side, as ExtraHands.gd.

const XH = preload("res://vr/ExtraHands.gd")

const SHAPES := [["sphere", "Ball"], ["box", "Box"], ["capsule", "Capsule (finger)"], ["cylinder", "Cylinder"], ["cone", "Cone (claw)"], ["torus", "Ring"], ["shard", "Crystal"]]
const LOOKS := [["toon", "Cartoon"], ["shiny", "Shiny cartoon"], ["glow", "Glowing"], ["flat", "Flat colour"]]
const MAX_PARTS := 48
const POS_MAX := 150.0 # mm from the controller
const SIZE_MIN := 2.0 # mm
const SIZE_MAX := 200.0
const SCALE_MIN := 50
const SCALE_MAX := 200
const CODE_PREFIX := "CHH1:"

static func shape_name(id: String) -> String:
	for s in SHAPES:
		if s[0] == id:
			return s[1]
	return "Part"

static func _has(list: Array, id: String) -> bool:
	for e in list:
		if e[0] == id:
			return true
	return false

static func blank() -> Dictionary:
	return {mirror = true, outline = true, outline_color = Color("14141a"), scale = 100, parts = []}

# a new part (mm, degrees)
static func part(shape: String = "sphere") -> Dictionary:
	var size := Vector3(30, 30, 30)
	if shape == "capsule" or shape == "cone" or shape == "shard":
		size = Vector3(16, 16, 50)
	elif shape == "cylinder":
		size = Vector3(30, 30, 20)
	elif shape == "torus":
		size = Vector3(40, 40, 8)
	return {shape = shape if _has(SHAPES, shape) else "sphere", pos = Vector3(0, 0, -30), rot = Vector3.ZERO, size = size, color = Color(1, 1, 1), look = "toon"}

static func _vec(text: String, lo: float, hi: float, fallback: Vector3) -> Vector3:
	var p := text.split(",")
	if p.size() != 3:
		return fallback
	return Vector3(clamp(float(p[0]), lo, hi), clamp(float(p[1]), lo, hi), clamp(float(p[2]), lo, hi))

static func _hex(text: String, fallback: Color) -> Color:
	var t := text.strip_edges().trim_prefix("#")
	if t.length() != 6 or not t.is_valid_hex_number():
		return fallback
	return Color(t)

# lines -> a design; anything that isn't one comes out as an empty hand
static func parse(lines) -> Dictionary:
	var d := blank()
	if lines is Dictionary:
		lines = encode(lines) # (a copy, checked)
	if not (lines is Array) and not (lines is PoolStringArray):
		return d
	for raw in lines:
		var line := String(raw).strip_edges()
		if line.length() > 200 or line == "":
			continue
		var f := line.split(";")
		if f[0] == "H1":
			for kv in f:
				var p := String(kv).split("=")
				if p.size() != 2:
					continue
				match p[0]:
					"m": d.mirror = p[1] == "1"
					"o": d.outline = p[1] == "1"
					"oc": d.outline_color = _hex(p[1], d.outline_color)
					"s": d.scale = int(clamp(int(p[1]), SCALE_MIN, SCALE_MAX))
			continue
		if f.size() != 6 or not _has(SHAPES, f[0]) or d.parts.size() >= MAX_PARTS:
			continue
		d.parts.append({
			shape = f[0],
			pos = _vec(f[1], -POS_MAX, POS_MAX, Vector3.ZERO),
			rot = _vec(f[2], -180.0, 180.0, Vector3.ZERO),
			size = _vec(f[3], SIZE_MIN, SIZE_MAX, Vector3(30, 30, 30)),
			color = _hex(f[4], Color(1, 1, 1)),
			look = f[5] if _has(LOOKS, f[5]) else "toon",
		})
	return d

static func _n(v: float) -> String:
	# (whole numbers, or one decimal: short lines)
	var r: float = stepify(v, 0.1)
	return str(int(r)) if is_equal_approx(r, round(r)) else "%.1f" % r

static func _v3(v: Vector3) -> String:
	return "%s,%s,%s" % [_n(v.x), _n(v.y), _n(v.z)]

static func encode(d: Dictionary) -> Array:
	var out := ["H1;m=%d;o=%d;oc=%s;s=%d" % [1 if d.get("mirror", true) else 0, 1 if d.get("outline", true) else 0, Color(d.get("outline_color", Color("14141a"))).to_html(false), int(d.get("scale", 100))]]
	for p in d.get("parts", []):
		if out.size() > MAX_PARTS:
			break
		out.append("%s;%s;%s;%s;%s;%s" % [p.shape, _v3(p.pos), _v3(p.rot), _v3(p.size), Color(p.color).to_html(false), p.look])
	return out

# a code to share a hand with (text: copy, paste)
static func code_of(d: Dictionary) -> String:
	return CODE_PREFIX + Marshalls.utf8_to_base64(PoolStringArray(encode(d)).join("\n"))

# -> a design, or null when the text isn't a hand code
static func from_code(text: String):
	var t := text.strip_edges()
	if not t.begins_with(CODE_PREFIX) or t.length() > 20000:
		return null
	var raw := Marshalls.base64_to_utf8(t.substr(CODE_PREFIX.length()))
	if raw == "" or not raw.begins_with("H1"):
		return null
	var d := parse(Array(raw.split("\n")))
	return d if d.parts.size() > 0 else null

# --- the mesh --------------------------------------------------------------------

static func _torus() -> Mesh:
	# (a ring around Z, 1 across, 0.3 thick)
	var st := XH._st()
	var R := 0.35
	var r := 0.15
	var seg := 24
	var ring := 10
	for i in range(seg):
		for j in range(ring):
			var quad := []
			for c in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var a: float = TAU * (i + c[0]) / seg
				var b: float = TAU * (j + c[1]) / ring
				var n := Vector3(cos(a) * cos(b), sin(a) * cos(b), sin(b))
				quad.append([Vector3(cos(a) * R, sin(a) * R, 0) + n * r, n])
			for k in [0, 2, 1, 0, 3, 2]:
				st.add_normal(quad[k][1])
				st.add_vertex(quad[k][0])
	return st.commit()

# one part's shape, `size` (metres) across, its long way along Z
static func _shape(shape: String, size: Vector3) -> Mesh:
	match shape:
		"box":
			return XH._box(size)
		"capsule":
			var r: float = min(size.x, size.y) / 2.0
			var m: Mesh = XH._capsule(r, max(size.z, r * 2.0 + 0.0002))
			return XH._scaled(m, Vector3(size.x / (2.0 * r), size.y / (2.0 * r), 1.0))
		"cylinder":
			return _turned(XH._scaled(XH._cyl(0.5, 1.0, 24), Vector3(size.x, size.z, size.y)), Basis(Vector3.RIGHT, PI / 2))
		"cone":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 20
			c.rings = 1
			# (the point forward, along -Z)
			return _turned(XH._scaled(c, Vector3(size.x, size.z, size.y)), Basis(Vector3.RIGHT, -PI / 2))
		"torus":
			return XH._scaled(_torus(), Vector3(size.x, size.y, size.z / 0.3))
		"shard":
			var st := XH._st()
			XH._shard(st, Vector3(0, 0, 0.5), Vector3(0, 0, -0.5), 0.5)
			return XH._scaled(st.commit(), size)
	return XH._sphere(size / 2.0)

static func _turned(m: Mesh, b: Basis) -> Mesh:
	var st := XH._st()
	st.append_from(m, 0, Transform(b, Vector3.ZERO))
	return st.commit()

static func _xform(p: Dictionary, scale: float) -> Transform:
	var r: Vector3 = p.rot
	return Transform(Basis(Vector3(deg2rad(r.x), deg2rad(r.y), deg2rad(r.z))), Vector3(p.pos) * 0.001 * scale)

static func _material(look: String, c: Color) -> Material:
	match look:
		"glow": return XH._glow_mat(c.lightened(0.6), c)
		"flat": return XH._toon(c, c, c, 0.0)
		"shiny": return XH._toon(c.lightened(0.25), c, c.darkened(0.28), 1.0)
	return XH._toon(c.lightened(0.25), c, c.darkened(0.28), 0.0)

# the right hand of a design (lines or a Dictionary); only_part: just that part (the editor's highlight)
static func build(design, only_part: int = -1) -> ArrayMesh:
	var d: Dictionary = design if design is Dictionary else parse(design)
	var mesh := ArrayMesh.new()
	var scale: float = clamp(float(d.get("scale", 100)), SCALE_MIN, SCALE_MAX) / 100.0
	var groups := {} # look|colour -> [SurfaceTool, look, colour]
	var line := XH._st()
	var lined := 0
	var parts: Array = d.get("parts", [])
	for i in range(parts.size()):
		if only_part >= 0 and i != only_part:
			continue
		var p: Dictionary = parts[i]
		var m: Mesh = _shape(p.shape, Vector3(p.size) * 0.001 * scale)
		var t: Transform = _xform(p, scale)
		var key := "%s|%s" % [p.look, Color(p.color).to_html(false)]
		if not groups.has(key):
			groups[key] = [XH._st(), p.look, Color(p.color)]
		XH._add(groups[key][0], m, t)
		if p.look != "glow":
			XH._add(line, m, t)
			lined += 1
	if d.get("outline", true) and lined > 0 and only_part < 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, line.commit_to_arrays())
		mesh.surface_set_material(0, XH._line_mat(Color(d.get("outline_color", Color("14141a"))), 0.0021))
	for key in groups:
		var g: Array = groups[key]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g[0].commit_to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(g[1], g[2]))
	return mesh

# [left, right] meshes, or null for a design with no parts
static func pair(design):
	var d: Dictionary = design if design is Dictionary else parse(design)
	if d.parts.empty():
		return null
	var r := build(d)
	if not d.get("mirror", true):
		return [r, r]
	return [load("res://vr/VRPlayer.gd")._mirrored(r), r]

# how far in front of the controller the hand reaches, metres (the beam starts there)
static func tip(design) -> float:
	var d: Dictionary = design if design is Dictionary else parse(design)
	var scale: float = clamp(float(d.get("scale", 100)), SCALE_MIN, SCALE_MAX) / 100.0
	var far := 0.0
	for p in d.parts:
		var t: Transform = _xform(p, scale)
		var h: Vector3 = Vector3(p.size) * 0.0005 * scale
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					far = max(far, -t.xform(Vector3(h.x * sx, h.y * sy, h.z * sz)).z)
	return clamp(far * 0.92, 0.0, 0.3) # (a box's corners reach a little past its shape)

# --- My hands: the hands you saved, to load, change and save again ---------------
# user://vr_hands.json: [{"name": ..., "lines": [...]}], newest first. The
# Hand Creator's "Start from" lists them after the hands that come with the
# game; one downloaded in the Content Browser lands here too.

const LIB_FILE := "user://vr_hands.json"
const LIB_MAX := 100
const FILE_EXT := "chand" # a hand as a file (the Content Browser's uploads): its lines, one a row

static func library() -> Array:
	var f := File.new()
	if f.open(Globals.p(LIB_FILE), File.READ) != OK:
		return []
	var p = JSON.parse(f.get_as_text())
	f.close()
	var out := []
	if p.error == OK and p.result is Array:
		for e in p.result:
			if e is Dictionary and e.get("lines") is Array and String(e.get("name", "")) != "":
				out.append({"name": String(e.name), "lines": e.lines})
	return out

static func _library_write(list: Array):
	var f := File.new()
	if f.open(Globals.p(LIB_FILE), File.WRITE) == OK:
		f.store_string(JSON.print(list))
		f.close()

static func clean_name(name: String) -> String:
	var n := name.strip_edges().replace("\n", " ").left(40)
	return n if n != "" else "My hand"

# saves a design under a name (one with that name already is replaced) -> the name it has
static func library_put(name: String, design) -> String:
	var n := clean_name(name)
	var lines: Array = encode(design) if design is Dictionary else Array(design)
	var list := library()
	for i in range(list.size() - 1, -1, -1):
		if String(list[i].name).to_lower() == n.to_lower():
			list.remove(i)
	list.push_front({"name": n, "lines": lines})
	if list.size() > LIB_MAX:
		list.resize(LIB_MAX)
	_library_write(list)
	return n

static func library_remove(name: String) -> bool:
	var list := library()
	for i in list.size():
		if String(list[i].name).to_lower() == name.strip_edges().to_lower():
			list.remove(i)
			_library_write(list)
			return true
	return false

# the name a design is saved under ("" if it isn't)
static func library_name_of(design) -> String:
	var lines: Array = encode(design) if design is Dictionary else Array(design)
	var sig := PoolStringArray(lines).join("\n")
	for e in library():
		if PoolStringArray(e.lines).join("\n") == sig:
			return String(e.name)
	return ""

# a hand as a file, and back (null when the file isn't one)
static func write_file(path: String, design) -> bool:
	var lines: Array = encode(design) if design is Dictionary else Array(design)
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		return false
	f.store_string(PoolStringArray(lines).join("\n") + "\n")
	f.close()
	return true

static func read_file(path: String):
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return null
	var text := f.get_as_text()
	f.close()
	var lines := []
	for l in text.replace("\r", "").split("\n", false):
		if l.strip_edges() != "":
			lines.append(l.strip_edges())
	if lines.empty() or not String(lines[0]).begins_with("H1"):
		return null
	var d := parse(lines)
	return d if not d.parts.empty() else null

# --- hands to start from ---------------------------------------------------------

const PRESETS := [
	["Rounded hand", [
		"H1;m=1;o=1;oc=14141a;s=100",
		"sphere;0,0,4;0,0,0;86,40,80;ffd9b8;toon",
		"capsule;-28,1,-45;0,-5,0;22,22,62;ffd9b8;toon",
		"capsule;-9.5,1,-52;0,-1,0;23,23,68;ffd9b8;toon",
		"capsule;9.5,1,-50;0,1,0;23,23,65;ffd9b8;toon",
		"capsule;28,1,-41;0,5,0;21,21,54;ffd9b8;toon",
		"capsule;-51,-3,-13;0,33,0;25,25,60;ffd9b8;toon",
	]],
	["Blocky hand", [
		"H1;m=1;o=1;oc=14141a;s=100",
		"box;0,0,10;0,0,0;80,24,80;7ad1ff;toon",
		"box;-30,0,-52;0,0,0;16,18,44;7ad1ff;toon",
		"box;-10,0,-56;0,0,0;16,18,52;7ad1ff;toon",
		"box;10,0,-55;0,0,0;16,18,50;7ad1ff;toon",
		"box;30,0,-49;0,0,0;16,18,38;7ad1ff;toon",
		"box;-52,0,-2;0,30,0;18,18,46;7ad1ff;toon",
	]],
	["Mitten", [
		"H1;m=1;o=1;oc=3a0d0d;s=100",
		"sphere;0,0,4;0,0,0;86,42,80;e63946;toon",
		"sphere;2,0,-42;0,0,0;80,38,74;e63946;toon",
		"capsule;-48,-2,-12;0,35,0;27,27,58;e63946;toon",
		"cylinder;0,0,52;0,0,0;74,34,22;ffffff;toon",
	]],
	["Robot claw", [
		"H1;m=1;o=1;oc=05080c;s=100",
		"cylinder;0,0,20;0,0,0;70,36,50;3a4352;shiny",
		"sphere;0,20,18;0,0,0;22,8,22;4df3ff;glow",
		"cone;-24,0,-40;0,-14,0;20,22,70;8894a8;shiny",
		"cone;0,0,-46;0,0,0;20,22,80;8894a8;shiny",
		"cone;24,0,-40;0,14,0;20,22,70;8894a8;shiny",
		"torus;0,0,-4;0,0,0;74,42,10;4df3ff;glow",
	]],
	["Orb", [
		"H1;m=0;o=0;oc=14141a;s=100",
		"sphere;0,0,-20;0,0,0;64,64,64;ffb4f1;glow",
		"torus;0,0,-20;70,0,0;96,96,8;ffffff;shiny",
		"torus;0,0,-20;-70,0,20;96,96,8;ffffff;shiny",
	]],
	["Crystals", [
		"H1;m=1;o=1;oc=2e0d59;s=100",
		"shard;0,0,10;0,0,0;60,44,90;bd80ff;shiny",
		"shard;-28,0,-38;0,-10,0;18,18,60;bd80ff;shiny",
		"shard;-9,0,-46;0,-3,0;18,18,70;d9b3ff;shiny",
		"shard;9,0,-44;0,3,0;18,18,66;bd80ff;shiny",
		"shard;28,0,-36;0,10,0;18,18,54;d9b3ff;shiny",
		"shard;-46,0,-6;0,40,0;18,18,50;bd80ff;shiny",
	]],
	["One ball (start from nothing)", [
		"H1;m=1;o=1;oc=14141a;s=100",
		"sphere;0,0,-20;0,0,0;60,60,60;ffffff;toon",
	]],
]
