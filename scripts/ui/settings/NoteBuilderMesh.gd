extends Reference

# Note Builder mesh generator (used by the "Note Builder" settings tab and by
# Savia.register_meshes). Builds a rounded regular polygon, optionally with a
# hole (border fill < 100%), extrudes it with a depth, adds an optional rounded
# bevel on the edges and an optional bulge on the front/back faces.
#
# The result has the same size/orientation as the default notes
# (res://assets/blocks/rounded.obj): fits in [-1, 1] on X/Y, centred on Z,
# with depth 0.2 by default.
#
# The built mesh is saved as an OBJ (+ MTL, which ObjParse needs) in
# user://note_builder/ and registered as the NoteMesh "note_builder".

const MESH_ID = "note_builder"
const MESH_NAME = "Custom (Note Builder)"
const DIR = "user://note_builder"
const OBJ_FILE = "note.obj"
const MTL_FILE = "note.mtl"
const PARAMS_FILE = "params.json"

const DEFAULTS = {
	"corners": 4,
	"rounding": 0.35,
	"fill": 1.0,
	"depth": 0.2,
	"bevel": 0.0,
	"bulge": 0.0,
}

static func dir_path() -> String:
	return Globals.p(DIR)

static func obj_path() -> String:
	return Globals.p(DIR).plus_file(OBJ_FILE)

static func sanitize(p) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if typeof(p) == TYPE_DICTIONARY:
		for k in DEFAULTS.keys():
			if p.has(k) and (typeof(p[k]) == TYPE_REAL or typeof(p[k]) == TYPE_INT):
				out[k] = float(p[k])
	out.corners = int(clamp(round(out.corners), 3, 14))
	out.rounding = clamp(out.rounding, 0.0, 1.0)
	out.fill = clamp(out.fill, 0.0, 1.0)
	out.depth = clamp(out.depth, 0.02, 1.0)
	out.bevel = clamp(out.bevel, 0.0, 1.0)
	out.bulge = clamp(out.bulge, 0.0, 1.0)
	return out

static func load_params() -> Dictionary:
	var f := File.new()
	var path: String = Globals.p(DIR).plus_file(PARAMS_FILE)
	if f.file_exists(path) and f.open(path, File.READ) == OK:
		var txt := f.get_as_text()
		f.close()
		var res := JSON.parse(txt)
		if res.error == OK:
			return sanitize(res.result)
	return DEFAULTS.duplicate()

# Called from Savia.register_meshes()
static func register(registry) -> void:
	if registry == null:
		return
	registry.add_item(NoteMesh.new(MESH_ID, MESH_NAME, obj_path(), "You"))

# ---------------------------------------------------------------- geometry

# Outline of the rounded polygon, offset inward by `off`.
# Returns [points: PoolVector2Array, normals: PoolVector2Array] (CCW).
static func _outline(n: int, R: float, rho: float, segs: int, off: float, center: Vector2) -> Array:
	var half := PI / n
	var cos_h := cos(half)
	var a := R * cos_h
	var a_o := max(a - off, 0.0)
	var rho_o := max(rho - off, 0.0)
	rho_o = min(rho_o, a_o)
	var c_o := (a_o - rho_o) / cos_h
	var theta0 := -PI / 2.0 + half
	var pts := PoolVector2Array()
	var nrm := PoolVector2Array()
	for k in range(n):
		var phi := theta0 + TAU * k / n
		var cdir := Vector2(cos(phi), sin(phi)) * c_o
		for i in range(segs + 1):
			var th := phi - half + (2.0 * half) * float(i) / segs
			var nd := Vector2(cos(th), sin(th))
			pts.append(cdir + nd * rho_o - center)
			nrm.append(nd)
	return [pts, nrm]

# Builds the mesh data: {"verts", "normals", "uvs", "tris"}. `tris` is in
# OBJ/counter-clockwise order (front face = CCW).
static func build(params: Dictionary) -> Dictionary:
	var p := sanitize(params)
	var n: int = p.corners
	var r: float = p.rounding
	var fill: float = p.fill
	var h: float = p.depth / 2.0
	var bevel: float = p.bevel
	var bulge: float = p.bulge

	var segs := 1
	if r > 0.001:
		segs = int(clamp(ceil(r * 36.0 / n) + 1, 2, 10))

	# Normalize so the outer outline fits in [-1, 1] like the default notes.
	var unit := _outline(n, 1.0, r * cos(PI / n), segs, 0.0, Vector2.ZERO)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for q in unit[0]:
		mn.x = min(mn.x, q.x); mn.y = min(mn.y, q.y)
		mx.x = max(mx.x, q.x); mx.y = max(mx.y, q.y)
	var half_ext := max((mx.x - mn.x), (mx.y - mn.y)) / 2.0
	var k_scale := 1.0 / max(half_ext, 0.0001)
	var center := (mn + mx) / 2.0 * k_scale
	var R := k_scale
	var a := R * cos(PI / n)
	var rho := r * a

	var solid := fill >= 0.999
	var rows := [] # each: [off, z, nf, nz]
	var bev_segs := 1
	var front := []
	if solid:
		var s := bevel * min(h, a * 0.4) * 0.999
		if s > 0.0005: bev_segs = 3
		else: s = 0.0
		var span := max(a - s, 0.0001)
		var bh := bulge * a * 0.35
		for i in range(bev_segs + 1):
			var b := (PI / 2.0) * float(i) / bev_segs
			front.append([s - s * cos(b), h - s + s * sin(b), cos(b), sin(b)])
		var rings := 1
		if bh > 0.0001: rings = 6
		for i in range(rings + 1):
			var u := float(i) / rings
			var z := h + bh * (1.0 - (1.0 - u) * (1.0 - u))
			var slope := bh * 2.0 * (1.0 - u) / span
			front.append([s + span * u, z, slope, 1.0])
		# back face from the centre outwards, then the front face back in
		for i in range(front.size() - 1, -1, -1):
			var fr = front[i]
			rows.append([fr[0], -fr[1], fr[2], -fr[3]])
		for fr in front:
			rows.append(fr)
	else:
		var t := a * max(fill, 0.04)
		var s := bevel * min(h, t * 0.45) * 0.999
		if s > 0.0005: bev_segs = 3
		else: s = 0.0
		var span := max(t - 2.0 * s, 0.0001)
		var bh := bulge * t * 0.35
		for i in range(bev_segs + 1):
			var b := (PI / 2.0) * float(i) / bev_segs
			front.append([s - s * cos(b), h - s + s * sin(b), cos(b), sin(b)])
		var rings := 1
		if bh > 0.0001: rings = 8
		for i in range(rings + 1):
			var u := float(i) / rings
			var z := h + bh * sin(PI * u)
			var slope := bh * PI * cos(PI * u) / span
			front.append([s + span * u, z, slope, 1.0])
		for i in range(bev_segs + 1):
			var g := (PI / 2.0) * float(i) / bev_segs
			front.append([t - s + s * sin(g), h - s + s * cos(g), -sin(g), cos(g)])
		for fr in front:
			rows.append(fr)
		for i in range(front.size() - 1, -1, -1):
			var fr = front[i]
			rows.append([fr[0], -fr[1], fr[2], -fr[3]])
		rows.append(front[0])

	var verts := PoolVector3Array()
	var normals := PoolVector3Array()
	var uvs := PoolVector2Array()
	var P := 0
	for row in rows:
		var ol := _outline(n, R, rho, segs, row[0], center)
		var pts: PoolVector2Array = ol[0]
		var nrm: PoolVector2Array = ol[1]
		P = pts.size()
		for j in range(P):
			var q: Vector2 = pts[j]
			verts.append(Vector3(q.x, q.y, row[1]))
			normals.append(Vector3(nrm[j].x * row[2], nrm[j].y * row[2], row[3]).normalized())
			uvs.append(Vector2(q.x * 0.5 + 0.5, q.y * 0.5 + 0.5))

	var tris := [] # Array (by reference) - Pool arrays are passed by value
	for i in range(rows.size() - 1):
		var r0 = rows[i]
		var r1 = rows[i + 1]
		if abs(r0[0] - r1[0]) < 1e-6 and abs(r0[1] - r1[1]) < 1e-6:
			continue # zero-area band (hard edge)
		for j in range(P):
			var j2 := (j + 1) % P
			var A := i * P + j
			var B := i * P + j2
			var C := (i + 1) * P + j2
			var D := (i + 1) * P + j
			_add_tri(verts, normals, tris, A, B, C)
			_add_tri(verts, normals, tris, A, C, D)
	return {"verts": verts, "normals": normals, "uvs": uvs, "tris": PoolIntArray(tris)}

static func _add_tri(verts: PoolVector3Array, normals: PoolVector3Array, tris: Array, a: int, b: int, c: int) -> void:
	var va := verts[a]
	var cr := (verts[b] - va).cross(verts[c] - va)
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(normals[a] + normals[b] + normals[c]) >= 0.0:
		tris.append(a); tris.append(b); tris.append(c)
	else:
		tris.append(a); tris.append(c); tris.append(b)

# Shaded mesh for previews (Godot uses clockwise front faces).
static func to_array_mesh(data: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var uvs := PoolVector2Array()
	for uv in data.uvs:
		uvs.append(Vector2(uv.x, 1.0 - uv.y))
	var src: PoolIntArray = data.tris
	var idx := PoolIntArray()
	idx.resize(src.size())
	var i := 0
	while i < src.size():
		idx[i] = src[i]
		idx[i + 1] = src[i + 2]
		idx[i + 2] = src[i + 1]
		i += 3
	arr[Mesh.ARRAY_VERTEX] = data.verts
	arr[Mesh.ARRAY_NORMAL] = data.normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if idx.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# Wireframe (unique triangle edges) for previews.
static func to_wire_mesh(data: Dictionary) -> ArrayMesh:
	var seen := {}
	var lines := PoolVector3Array()
	var src: PoolIntArray = data.tris
	var verts: PoolVector3Array = data.verts
	var i := 0
	while i < src.size():
		for e in [[src[i], src[i + 1]], [src[i + 1], src[i + 2]], [src[i + 2], src[i]]]:
			var lo: int = int(min(e[0], e[1]))
			var hi: int = int(max(e[0], e[1]))
			var key := lo * 1048576 + hi
			if seen.has(key):
				continue
			seen[key] = true
			if verts[lo].distance_squared_to(verts[hi]) < 1e-10:
				continue
			lines.append(verts[lo]); lines.append(verts[hi])
		i += 3
	var m := ArrayMesh.new()
	if lines.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = lines
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m

static func to_obj(data: Dictionary) -> String:
	var out := PoolStringArray()
	out.append("# Chromia Note Builder mesh")
	out.append("mtllib " + MTL_FILE)
	out.append("o NoteBuilder")
	for v in data.verts:
		out.append("v %.5f %.5f %.5f" % [v.x, v.y, v.z])
	for uv in data.uvs:
		out.append("vt %.5f %.5f" % [uv.x, uv.y])
	for nn in data.normals:
		out.append("vn %.4f %.4f %.4f" % [nn.x, nn.y, nn.z])
	out.append("usemtl Material")
	out.append("s off")
	var src: PoolIntArray = data.tris
	var i := 0
	while i < src.size():
		var a := src[i] + 1
		var b := src[i + 1] + 1
		var c := src[i + 2] + 1
		out.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % [a, a, a, b, b, b, c, c, c])
		i += 3
	return out.join("\n") + "\n"

# Saves params + OBJ/MTL. Returns OK or an error code.
static func save(params: Dictionary, data = null) -> int:
	var p := sanitize(params)
	if data == null:
		data = build(p)
	var d := Directory.new()
	var base := dir_path()
	if not d.dir_exists(base):
		var e := d.make_dir_recursive(base)
		if e != OK:
			return e
	var f := File.new()
	var err := f.open(base.plus_file(MTL_FILE), File.WRITE)
	if err != OK:
		return err
	f.store_string("newmtl Material\nKa 1.0 1.0 1.0\nKd 0.8 0.8 0.8\nKs 0.5 0.5 0.5\nd 1.0\nillum 2\n")
	f.close()
	# write to a temp file first so a half-written OBJ never gets loaded
	var tmp := base.plus_file(OBJ_FILE + ".tmp")
	err = f.open(tmp, File.WRITE)
	if err != OK:
		return err
	f.store_string(to_obj(data))
	f.close()
	if d.file_exists(obj_path()):
		d.remove(obj_path())
	err = d.rename(tmp, obj_path())
	if err != OK:
		return err
	err = f.open(base.plus_file(PARAMS_FILE), File.WRITE)
	if err != OK:
		return err
	f.store_string(to_json(p))
	f.close()
	return OK
