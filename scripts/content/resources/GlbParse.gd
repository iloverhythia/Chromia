extends Reference

# Note meshes from .glb files (binary glTF 2.0), read here: Godot 3's own glTF
# importer is for the editor, not every exported build (phones, Quest, web).
#
# Every mesh in the file's scene, with its node's position, rotation and size,
# goes into one mesh of plain triangles (no index list, so NoteManager can make
# it double-sided like an .obj). Positions, normals (worked out from the
# triangles when the file has none) and the first UVs; materials, textures,
# skins and animations are left out (notes have their own look). Compressed
# files (Draco, meshopt) aren't read.
#
# ObjParse.load_obj hands a file here when it starts with "glTF", whatever its
# name: a spectator's copy of your mesh is saved as <hash>.obj.

const MAGIC := 0x46546C67 # "glTF"
const CHUNK_JSON := 0x4E4F534A
const CHUNK_BIN := 0x004E4942
const MAX_VERTS := 3000000 # (a broken or huge file doesn't hang the game)

static func is_glb(path: String) -> bool:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return false
	var ok: bool = f.get_len() >= 12 and f.get_32() == MAGIC
	f.close()
	return ok

# -> ArrayMesh, or null when it can't be read
static func load_glb(path: String) -> Mesh:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return null
	var data: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	return from_buffer(data)

static func from_buffer(data: PoolByteArray) -> Mesh:
	var sp := StreamPeerBuffer.new()
	sp.data_array = data
	if data.size() < 20 or sp.get_u32() != MAGIC or sp.get_u32() != 2:
		return null
	var total: int = int(min(sp.get_u32(), data.size()))
	var json = null
	var bin := PoolByteArray()
	var at := 12
	while at + 8 <= total:
		sp.seek(at)
		var clen: int = sp.get_u32()
		var ctype: int = sp.get_u32()
		if clen < 0 or at + 8 + clen > total:
			break
		var chunk: PoolByteArray = data.subarray(at + 8, at + 8 + clen - 1) if clen > 0 else PoolByteArray()
		if ctype == CHUNK_JSON and json == null:
			var parsed = JSON.parse(chunk.get_string_from_utf8())
			if parsed.error == OK and parsed.result is Dictionary:
				json = parsed.result
		elif ctype == CHUNK_BIN and bin.size() == 0:
			bin = chunk
		at += 8 + clen
	if not (json is Dictionary):
		return null
	var g := {"json": json, "bin": StreamPeerBuffer.new(), "size": bin.size()}
	g.bin.data_array = bin
	# (plain Arrays: a Pool array read out of a Dictionary is a copy, and appending to it went nowhere)
	var out := {"v": [], "n": [], "uv": [], "has_uv": true}
	var nodes: Array = json.get("nodes", []) if json.get("nodes") is Array else []
	var roots := []
	var scenes = json.get("scenes")
	if scenes is Array and scenes.size() > 0:
		var si: int = int(json.get("scene", 0))
		var sc = scenes[si] if si >= 0 and si < scenes.size() else scenes[0]
		if sc is Dictionary and sc.get("nodes") is Array:
			roots = sc.nodes
	if roots.empty() and not nodes.empty():
		# (no scene: every node no other node lists as a child)
		var child := {}
		for n in nodes:
			if n is Dictionary and n.get("children") is Array:
				for c in n.children:
					child[int(c)] = true
		for i in range(nodes.size()):
			if not child.has(i):
				roots.append(i)
	if nodes.empty():
		# (meshes and no nodes: each as it is)
		var meshes = json.get("meshes", [])
		if meshes is Array:
			for mi in range(meshes.size()):
				_add_mesh(g, mi, Transform.IDENTITY, out)
	else:
		for r in roots:
			_walk(g, nodes, int(r), Transform.IDENTITY, out, 0)
	if out.v.size() < 3:
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PoolVector3Array(out.v)
	arr[Mesh.ARRAY_NORMAL] = PoolVector3Array(out.n)
	if out.has_uv and out.uv.size() == out.v.size():
		arr[Mesh.ARRAY_TEX_UV] = PoolVector2Array(out.uv)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

static func _walk(g: Dictionary, nodes: Array, i: int, parent: Transform, out: Dictionary, depth: int):
	if i < 0 or i >= nodes.size() or depth > 64 or not (nodes[i] is Dictionary):
		return
	var n: Dictionary = nodes[i]
	var t: Transform = parent * _node_transform(n)
	if n.has("mesh"):
		_add_mesh(g, int(n.mesh), t, out)
	if n.get("children") is Array:
		for c in n.children:
			_walk(g, nodes, int(c), t, out, depth + 1)

static func _node_transform(n: Dictionary) -> Transform:
	var m = n.get("matrix")
	if m is Array and m.size() == 16:
		# (column by column)
		return Transform(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
	var b := Basis()
	var r = n.get("rotation")
	if r is Array and r.size() == 4:
		b = Basis(Quat(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized())
	var s = n.get("scale")
	if s is Array and s.size() == 3:
		b = b * Basis().scaled(Vector3(float(s[0]), float(s[1]), float(s[2]))) # (scaled first, then turned)
	var o := Vector3.ZERO
	var tr = n.get("translation")
	if tr is Array and tr.size() == 3:
		o = Vector3(float(tr[0]), float(tr[1]), float(tr[2]))
	return Transform(b, o)

static func _add_mesh(g: Dictionary, mi: int, t: Transform, out: Dictionary):
	var meshes = g.json.get("meshes")
	if not (meshes is Array) or mi < 0 or mi >= meshes.size() or not (meshes[mi] is Dictionary):
		return
	var prims = meshes[mi].get("primitives")
	if not (prims is Array):
		return
	var nb: Basis = t.basis.inverse().transposed() # (normals follow the shape when it's stretched)
	for p in prims:
		if not (p is Dictionary) or int(p.get("mode", 4)) != 4: # (triangles only)
			continue
		var at = p.get("attributes")
		if not (at is Dictionary) or not at.has("POSITION"):
			continue
		var pos: Array = _accessor(g, int(at.POSITION))
		if pos.empty():
			continue
		var nor: Array = _accessor(g, int(at.NORMAL)) if at.has("NORMAL") else []
		var uv: Array = _accessor(g, int(at.TEXCOORD_0)) if at.has("TEXCOORD_0") else []
		if uv.size() != pos.size():
			out.has_uv = false
		var idx: Array
		if p.has("indices"):
			idx = _accessor(g, int(p.indices))
		else:
			idx = range(pos.size())
		if out.v.size() + idx.size() > MAX_VERTS:
			return
		# Godot's front faces go the other way round from glTF's: b and c swap
		for k in range(0, idx.size() - idx.size() % 3, 3):
			var tri := [int(idx[k]), int(idx[k + 2]), int(idx[k + 1])]
			if tri[0] >= pos.size() or tri[1] >= pos.size() or tri[2] >= pos.size() or tri[0] < 0 or tri[1] < 0 or tri[2] < 0:
				continue
			var a: Vector3 = t.xform(pos[tri[0]])
			var b: Vector3 = t.xform(pos[tri[1]])
			var c: Vector3 = t.xform(pos[tri[2]])
			var flat: Vector3 = (c - a).cross(b - a).normalized()
			var vs := [a, b, c]
			for j in range(3):
				out.v.append(vs[j])
				if nor.size() == pos.size():
					out.n.append((nb.xform(nor[tri[j]])).normalized())
				else:
					out.n.append(flat)
				if out.has_uv:
					out.uv.append(uv[tri[j]])

# an accessor's values: Vector3 (VEC3), Vector2 (VEC2) or numbers (SCALAR)
static func _accessor(g: Dictionary, ai: int) -> Array:
	var accs = g.json.get("accessors")
	var views = g.json.get("bufferViews")
	if not (accs is Array) or not (views is Array) or ai < 0 or ai >= accs.size() or not (accs[ai] is Dictionary):
		return []
	var acc: Dictionary = accs[ai]
	if not acc.has("bufferView"):
		return [] # (sparse-only or empty: not read)
	var vi: int = int(acc.bufferView)
	if vi < 0 or vi >= views.size() or not (views[vi] is Dictionary) or int(views[vi].get("buffer", 0)) != 0:
		return []
	var view: Dictionary = views[vi]
	var ctype: int = int(acc.get("componentType", 5126))
	var csize: int = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}.get(ctype, 0)
	var comps: int = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}.get(String(acc.get("type", "")), 0)
	var count: int = int(acc.get("count", 0))
	if csize == 0 or comps == 0 or count <= 0 or count > MAX_VERTS:
		return []
	var stride: int = int(view.get("byteStride", csize * comps))
	if stride <= 0:
		stride = csize * comps
	var base: int = int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	if base < 0 or base + stride * (count - 1) + csize * comps > g.size:
		return []
	var norm: bool = bool(acc.get("normalized", false))
	var sp: StreamPeerBuffer = g.bin
	var out := []
	out.resize(count)
	var vals := [0.0, 0.0, 0.0, 0.0]
	for i in range(count):
		sp.seek(base + i * stride)
		for c in range(comps):
			var v: float
			match ctype:
				5126: v = sp.get_float()
				5125: v = float(sp.get_u32())
				5123: v = float(sp.get_u16()) / (65535.0 if norm else 1.0)
				5122: v = max(float(sp.get_16()) / 32767.0, -1.0) if norm else float(sp.get_16())
				5121: v = float(sp.get_u8()) / (255.0 if norm else 1.0)
				_: v = max(float(sp.get_8()) / 127.0, -1.0) if norm else float(sp.get_8())
			vals[c] = v
		if comps == 1:
			out[i] = vals[0]
		elif comps == 2:
			out[i] = Vector2(vals[0], vals[1])
		else:
			out[i] = Vector3(vals[0], vals[1], vals[2])
	return out
