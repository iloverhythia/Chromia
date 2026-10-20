extends ViewportContainer
# The map editor's middle view, drawn like the game: same camera, your note
# mesh and note image, colorset, approach rate / spawn distance, fade in and
# half ghost, note size and opacity, note spin, approach squares, border,
# cursor (and its image / size / colour) and the background world, which
# reacts to hits like in a song. The materials come straight from song.tscn,
# so notes look exactly the same. The note maths follows NoteManager.gd's
# note_reposition(); gameplay mods (mirror, hard rock, ghost, chaos...) are left
# out so the map shows as it's mapped.

signal hit(col)

const MAX_NOTES = 400
const RES_META = "chromia_editor_game_res"

var page # EditorPage
var viewport: Viewport
var cam: Camera
var game: Spatial
var spawn: Spatial
var notes_mmi: MultiMeshInstance
var asq_mmi: MultiMeshInstance
var cursor: Spatial
var world: Node = null
var show_world := true
var hit_flash := true
var _built := false
var _note_scale := 0.45
var _last_ms := 0.0
var _colors: Array = []
var _hlpower := 0.65

# --- settings, read from Rhythia when the view is (re)built
var approach_rate := 40.0
var spawn_dist := 40.0
var fade_in_enabled := true
var fade_in_start := 8.0
var fade_in_end := 6.0
var fade_out_enabled := false
var fade_out_start := 3.0
var fade_out_end := 1.0
var fade_out_base := 1.0
var opacity := 1.0
var asq := false
var va_follow := false
var spin := false
var spin_basis := Basis()
var pushback := 0.1
var grid_parallax := 0.0

func is_built() -> bool:
	return _built

func _ready():
	stretch = true
	mouse_filter = MOUSE_FILTER_IGNORE
	viewport = Viewport.new()
	viewport.own_world = true
	viewport.world = World.new()
	viewport.msaa = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(viewport)
	# the container only sizes its viewport when it is resized itself
	viewport.size = rect_size
	connect("resized", self, "_fit_viewport")

func _fit_viewport():
	if viewport and rect_size.x > 0 and rect_size.y > 0:
		viewport.size = rect_size

# Pieces of the real song scene: materials, border, cursor mesh. Taken once.
static func _game_resources() -> Dictionary:
	var root = Engine.get_main_loop().root
	if root.has_meta(RES_META):
		return root.get_meta(RES_META)
	var res := {}
	var packed = load("res://scenes/song.tscn")
	if packed:
		var inst = packed.instance()
		var sp = inst.get_node_or_null("Game/Spawn")
		if sp:
			res["solid"] = sp.note_solid_mat.duplicate() if sp.note_solid_mat else null
			res["transparent"] = sp.note_transparent_mat.duplicate() if sp.note_transparent_mat else null
			res["asq"] = sp.asq_mat.duplicate() if sp.asq_mat else null
			var se = sp.get("scoreEffect")
			if se is Node and is_instance_valid(se) and not se.is_inside_tree():
				se.free()
			var outer = sp.get_node_or_null("Outer")
			if outer:
				res["outer_mesh"] = outer.mesh
				res["outer_mat"] = outer.get("material/0").duplicate() if outer.get("material/0") else null
				res["outer_transform"] = outer.transform
			var cm = sp.get_node_or_null("Cursor/Mesh")
			if cm:
				res["cursor_mesh"] = cm.mesh
				res["cursor_mat"] = cm.get("material/0").duplicate() if cm.get("material/0") else null
				res["cursor_transform"] = cm.transform
		var c = inst.get_node_or_null("Camera")
		if c:
			res["cam_far"] = c.far
			res["cam_near"] = c.near
		inst.free()
	root.set_meta(RES_META, res)
	return res

func build():
	if _built:
		return
	_built = true
	_read_settings()
	var res = _game_resources()

	cam = Camera.new()
	cam.current = true
	cam.fov = Rhythia.get("fov")
	cam.far = res.get("cam_far", 500.0)
	cam.near = res.get("cam_near", 0.05)
	cam.transform.origin = Vector3(0, 0, 3.75)
	viewport.add_child(cam)

	game = Spatial.new()
	game.name = "Game"
	game.set_script(load("res://scripts/editor/EditorGameSignals.gd"))
	viewport.add_child(game)
	connect("hit", game, "emit_hit")
	spawn = Spatial.new()
	spawn.name = "Spawn"
	spawn.transform.origin = Vector3(-1, 1, 0)
	game.add_child(spawn)

	# border (Outer), coloured / textured like NoteManager._ready()
	if res.has("outer_mesh"):
		var outer = MeshInstance.new()
		outer.mesh = res["outer_mesh"]
		outer.transform = res["outer_transform"]
		var om = res.get("outer_mat")
		if om:
			om = om.duplicate()
			var bt = Rhythia.get_selected_border_texture()
			if bt != null:
				om.albedo_texture = bt
			om.albedo_color = Rhythia.border_color
			outer.set("material/0", om)
		spawn.add_child(outer)

	# notes
	notes_mmi = MultiMeshInstance.new()
	notes_mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	mm.mesh = _note_mesh(res)
	mm.instance_count = MAX_NOTES
	mm.visible_instance_count = 0
	notes_mmi.multimesh = mm
	spawn.add_child(notes_mmi)

	if asq and res.get("asq"):
		asq_mmi = MultiMeshInstance.new()
		asq_mmi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var am = MultiMesh.new()
		am.transform_format = MultiMesh.TRANSFORM_3D
		am.color_format = MultiMesh.COLOR_8BIT
		var q = QuadMesh.new()
		q.size = Vector2(3.35, 3.35)
		q.surface_set_material(0, res["asq"])
		am.mesh = q
		am.instance_count = MAX_NOTES
		am.visible_instance_count = 0
		asq_mmi.multimesh = am
		spawn.add_child(asq_mmi)

	# cursor, like Cursor._ready()
	cursor = Spatial.new()
	cursor.transform.origin = Vector3(1, -1, 0)
	spawn.add_child(cursor)
	if res.has("cursor_mesh"):
		var cmi = MeshInstance.new()
		cmi.mesh = res["cursor_mesh"]
		cmi.transform = res["cursor_transform"]
		cmi.scale = Vector3.ONE * Rhythia.cursor_scale
		var cmat = res.get("cursor_mat")
		if cmat:
			cmat = cmat.duplicate()
			var img = Globals.imageLoader.load_if_exists("user://cursor")
			if img:
				cmat.albedo_color = Color(1, 1, 1)
				cmat.albedo_texture = img
			if Rhythia.cursor_color_type == Globals.CURSOR_NOTE_COLOR and not _colors.empty():
				cmat.albedo_color = _colors[-1]
			elif Rhythia.cursor_color_type == Globals.CURSOR_CUSTOM_COLOR:
				cmat.albedo_color = Rhythia.cursor_color
			cmi.set("material/0", cmat)
		cursor.add_child(cmi)
	cursor.visible = Rhythia.show_cursor

	set_world_visible(show_world)

func _note_mesh(res: Dictionary) -> Mesh:
	var mesh: Mesh = null
	var path := String(Rhythia.selected_mesh.path) if Rhythia.selected_mesh else ""
	if path != "" and ("user://" in path or not path.begins_with("res://")):
		var m = ObjParse.load_obj(path)
		if m != null:
			mesh = _double_sided(m)
	elif path != "":
		mesh = load(path)
	if mesh == null or mesh.get_surface_count() == 0:
		mesh = load("res://assets/blocks/rounded.obj")
	if mesh is ArrayMesh:
		mesh = mesh.duplicate()
	var solid = res.get("solid")
	var transparent = res.get("transparent")
	var img = Globals.imageLoader.load_if_exists("user://note")
	if img:
		for m in [solid, transparent]:
			if m:
				m.set_shader_param("image", img)
				m.set_shader_param("use_image", true)
	if solid:
		mesh.surface_set_material(0, solid)
	if mesh.get_surface_count() > 1 and transparent:
		mesh.surface_set_material(1, transparent)
	if mesh.get_surface_count() > 2 and solid:
		mesh.surface_set_material(2, solid)
	return mesh

# same as NoteManager._double_sided: imported meshes may face away
func _double_sided(src: Mesh) -> Mesh:
	if not (src is ArrayMesh):
		return src
	var out := ArrayMesh.new()
	for i in range(src.get_surface_count()):
		var arr: Array = src.surface_get_arrays(i)
		var verts = arr[Mesh.ARRAY_VERTEX]
		if verts == null or verts.size() == 0 or arr[Mesh.ARRAY_INDEX] != null:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
			continue
		var n: int = verts.size() - verts.size() % 3
		var nv := PoolVector3Array(verts)
		var has_n: bool = arr[Mesh.ARRAY_NORMAL] != null and arr[Mesh.ARRAY_NORMAL].size() == verts.size()
		var has_uv: bool = arr[Mesh.ARRAY_TEX_UV] != null and arr[Mesh.ARRAY_TEX_UV].size() == verts.size()
		var nn := PoolVector3Array(arr[Mesh.ARRAY_NORMAL]) if has_n else PoolVector3Array()
		var nuv := PoolVector2Array(arr[Mesh.ARRAY_TEX_UV]) if has_uv else PoolVector2Array()
		for t in range(0, n, 3):
			for k in [0, 2, 1]:
				nv.append(verts[t + k])
				if has_n: nn.append(-arr[Mesh.ARRAY_NORMAL][t + k])
				if has_uv: nuv.append(arr[Mesh.ARRAY_TEX_UV][t + k])
		var out_arr := []
		out_arr.resize(Mesh.ARRAY_MAX)
		out_arr[Mesh.ARRAY_VERTEX] = nv
		if has_n: out_arr[Mesh.ARRAY_NORMAL] = nn
		if has_uv: out_arr[Mesh.ARRAY_TEX_UV] = nuv
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arr)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
	return out

func _read_settings():
	approach_rate = float(Rhythia.get("approach_rate"))
	spawn_dist = float(Rhythia.get("spawn_distance"))
	opacity = Rhythia.note_opacity
	asq = Rhythia.note_visual_approach
	va_follow = Rhythia.visual_approach_follow
	pushback = 0.1 if Rhythia.do_note_pushback else 0.0
	_hlpower = 0.1 * float(Rhythia.get("parallax"))
	grid_parallax = float(Rhythia.get("grid_parallax")) * 0.1
	_note_scale = 0.45 * Rhythia.note_size * (Rhythia.note_hitbox_size / 1.14)
	fade_out_enabled = false
	if Rhythia.half_ghost:
		fade_out_enabled = true
		fade_out_start = (12.0 / 50.0) * approach_rate
		fade_out_end = (3.0 / 50.0) * approach_rate
		fade_out_base = clamp(Rhythia.half_ghost_strength, 0.1, 1.0)
	fade_in_enabled = float(Rhythia.get("fade_length")) != 0
	if fade_in_enabled:
		fade_in_start = spawn_dist
		fade_in_end = spawn_dist * (1.0 - float(Rhythia.get("fade_length")))
	spin = Rhythia.note_spin_x != 0 or Rhythia.note_spin_y != 0 or Rhythia.note_spin_z != 0
	if spin:
		spin_basis = Basis().rotated(Vector3(1, 0, 0), Rhythia.note_spin_x / 2000).rotated(Vector3(0, 1, 0), Rhythia.note_spin_y / 2000).rotated(Vector3(0, 0, 1), Rhythia.note_spin_z / 2000)
	_colors = Rhythia.selected_colorset.colors if Rhythia.selected_colorset else [Color(1, 1, 1)]

func set_world_visible(on: bool):
	show_world = on
	if not _built:
		return
	if on and world == null and Rhythia.selected_space:
		var packed = load(Rhythia.selected_space.path)
		if packed is PackedScene:
			world = packed.instance()
			world.name = "Space"
			viewport.add_child(world)
	elif not on and world != null:
		world.queue_free()
		world = null
	# no world: plain black like the void
	if world == null:
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0)
		cam.environment = env
	else:
		cam.environment = null

static func linstep(a: float, b: float, x: float) -> float:
	if a == b:
		return float(x >= a)
	return clamp((x - a) / (b - a), 0.0, 1.0)

# --- grid <-> screen (camera never rotates, so the grid plane maps to a
# straight rectangle on screen)

func world_of(g: Vector2) -> Vector3:
	return spawn.transform.origin + Vector3(g.x, -g.y, 0)

func screen_of(g: Vector2) -> Vector2:
	return cam.unproject_position(world_of(g))

# [origin of cell (0,0)'s top-left, cell size] in this control's coordinates
func grid_geom() -> Array:
	var a := screen_of(Vector2(-0.5, -0.5))
	var b := screen_of(Vector2(0.5, -0.5))
	return [a, b.x - a.x]

func grid_at(p: Vector2) -> Vector2:
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if abs(dir.z) < 0.00001:
		return Vector2(-100, -100)
	var t := -from.z / dir.z
	var hitp := from + dir * t - spawn.transform.origin
	return Vector2(hitp.x, -hitp.y)

# --- per frame

func _process(_delta):
	if not _built or page == null or page.project == null or not is_visible_in_tree():
		return
	var now: float = page.time_ms
	var notes: Array = page.project.notes
	var ar: float = page.approach_rate_3d()
	# camera parallax around the cursor (NoteManager.do_half_lock)
	var cp = page.cursor_pos()
	var cpos: Vector2 = Vector2(1, 1) if cp == null else cp
	var centeroff := Vector2(cpos.x - 1, -(cpos.y - 1))
	cam.transform.origin = Vector3(centeroff.x * _hlpower * 0.25, centeroff.y * _hlpower * 0.25, 3.75)
	spawn.transform.origin = Vector3(-(centeroff.x * 0.25 * grid_parallax) - 1, -(centeroff.y * 0.25 * grid_parallax) + 1, 0)
	cursor.transform.origin = Vector3(cpos.x, -cpos.y, 0)
	cursor.visible = Rhythia.show_cursor and page.show_cursor

	var mm: MultiMesh = notes_mmi.multimesh
	var am: MultiMesh = asq_mmi.multimesh if asq_mmi else null
	var speed := ar
	var max_ms := now + spawn_dist / max(speed, 0.001) * 1000.0
	var i0: int = page.project.lower_bound(now - pushback / max(speed, 0.001) * 1000.0 - 1)
	var slot := 0
	var i := i0
	var ncol := _colors.size()
	while i < notes.size() and slot < MAX_NOTES:
		var n = notes[i]
		if n[2] > max_ms:
			break
		var dist: float = speed * (n[2] - now) / 1000.0
		if dist >= -pushback:
			var t := Transform().scaled(Vector3.ONE * _note_scale)
			if spin:
				t.basis = spin_basis * t.basis
			t.origin = Vector3(n[0], -n[1], -dist)
			var alpha := opacity
			if fade_in_enabled or fade_out_enabled:
				var fi := 1.0
				var fo := 1.0
				if fade_in_enabled:
					fi = pow(linstep(fade_in_start, fade_in_end, dist), 1.3) * opacity
				if fade_out_enabled:
					fo = ((1 - fade_out_base) + (pow(linstep(fade_out_end, fade_out_start, dist), 1.3) * fade_out_base)) * opacity
				alpha = min(fi, fo)
			var col: Color = _colors[i % ncol] if ncol > 0 else Color(1, 1, 1)
			mm.set_instance_transform(slot, t)
			mm.set_instance_color(slot, Color(col.r, col.g, col.b, col.a * alpha))
			if am:
				var sc := (linstep(0, spawn_dist, dist) + 0.6) * 0.4
				var at := Transform().scaled(Vector3(sc, sc, sc))
				at.origin = t.origin
				if not va_follow:
					at.origin.z = 0
				am.set_instance_transform(slot, at)
				am.set_instance_color(slot, Color(1, 1, 1, pow(linstep(spawn_dist, 0, dist), 1.7)))
			slot += 1
		i += 1
	mm.visible_instance_count = slot
	if am:
		am.visible_instance_count = slot

	# hits while playing: the world flashes like in a song
	if page.playing and hit_flash and now > _last_ms:
		var j: int = page.project.lower_bound(_last_ms + 0.001)
		if j < notes.size() and notes[j][2] <= now and ncol > 0:
			emit_signal("hit", _colors[j % ncol])
	_last_ms = now
