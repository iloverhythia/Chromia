extends Spatial

# The 3D part of the Settings preview (SettingsPreview.gd): the song's own
# pieces, set up from your settings the way the song sets them up, so what you
# see is what a song shows:
# - notes: your note mesh (Settings > Meshes, or a custom .obj) with the song's
#   note materials (and your note picture), your colorset, note size (and the
#   hitbox it goes with), opacity, fade, half ghost and spin, coming in at your
#   approach rate from your spawn distance
# - the grid's border: the song's border mesh with your border picture and
#   colour, when Enable Border is on
# - the cursor: the song's cursor mesh with your cursor picture, size, colour
#   (custom, rainbow or note colour) and spin
# - the camera: your FOV, and the camera / grid parallax and Spin worked out
#   like the song does (NoteManager.do_half_lock / do_spin)
# - your hit effect, spawned like the song spawns it
# The meshes and materials are read from scenes/song.tscn (nothing of the song
# runs). Things that change are picked up while the preview is open.

const SONG := "res://scenes/song.tscn"
const CURSOR_OFFSET := Vector3(1, -1, 0)
const MAX_NOTES := 64

var cam: Camera
var spawn: Spatial
var notes: MultiMeshInstance
var outer: MeshInstance
var cursor: Spatial
var cursor_mesh: MeshInstance
var _fx_tpl = null
var _fx_id := ""
var _fx_pool: Array = []
var _sig := ""
var _check := 0.0
var _spin_deg := 0.0

static func _song_parts() -> Dictionary:
	var root: Viewport = Engine.get_main_loop().root
	if root.has_meta("settings_preview_parts"):
		return root.get_meta("settings_preview_parts")
	var out := {}
	var ps = load(SONG)
	if ps is PackedScene:
		var st: SceneState = ps.get_state()
		for i in st.get_node_count():
			var p := String(st.get_node_path(i))
			for j in st.get_node_property_count(i):
				out[p + ":" + st.get_node_property_name(i, j)] = st.get_node_property_value(i, j)
	root.set_meta("settings_preview_parts", out)
	return out

func _ready():
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.028, 0.045)
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	cam = Camera.new()
	cam.current = true
	cam.far = 500.0
	cam.transform.origin = Vector3(0, 0, 3.75)
	add_child(cam)
	spawn = Spatial.new()
	spawn.name = "Spawn"
	spawn.transform.origin = Vector3(-1, 1, 0)
	add_child(spawn)
	_build()

# settings that need the pieces made again
func _signature() -> String:
	var m = Rhythia.selected_mesh
	var b = Rhythia.selected_border
	var fx = Rhythia.selected_hit_effect
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [
		m.path if m else "", b.path if b else "", Rhythia.enable_border, Rhythia.border_color,
		fx.id if fx else "", Rhythia.show_hit_effect, Rhythia.note_size, Rhythia.note_hitbox_size,
	]

func _build():
	_sig = _signature()
	var parts := _song_parts()
	for n in [notes, outer, cursor]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	# the border
	outer = MeshInstance.new()
	outer.mesh = parts.get("./Game/Spawn/Outer:mesh")
	var t = parts.get("./Game/Spawn/Outer:transform")
	if t is Transform:
		outer.transform = t
	var om = parts.get("./Game/Spawn/Outer:material/0")
	if om is Material:
		om = om.duplicate()
		var bt = Rhythia.get_selected_border_texture()
		if bt != null:
			om.albedo_texture = bt
		om.albedo_color = Rhythia.border_color
		outer.set_surface_material(0, om)
	outer.visible = Rhythia.enable_border
	spawn.add_child(outer)
	# the notes
	notes = MultiMeshInstance.new()
	notes.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	mm.mesh = _note_mesh(parts)
	mm.instance_count = MAX_NOTES
	mm.visible_instance_count = 0
	notes.multimesh = mm
	spawn.add_child(notes)
	# the cursor
	cursor = Spatial.new()
	cursor.transform.origin = CURSOR_OFFSET
	cursor_mesh = MeshInstance.new()
	cursor_mesh.mesh = parts.get("./Game/Spawn/Cursor/Mesh:mesh")
	var ct = parts.get("./Game/Spawn/Cursor/Mesh:transform")
	if ct is Transform:
		cursor_mesh.transform = ct
	var cm = parts.get("./Game/Spawn/Cursor/Mesh:material/0")
	if cm is Material:
		cm = cm.duplicate()
		var img = Globals.imageLoader.load_if_exists("user://cursor")
		if img:
			cm.albedo_color = Color(1, 1, 1)
			cm.albedo_texture = img
		cursor_mesh.set_surface_material(0, cm)
	cursor.add_child(cursor_mesh)
	spawn.add_child(cursor)
	_spin_deg = 0.0
	# the hit effect
	for c in _fx_pool:
		if is_instance_valid(c):
			c.queue_free()
	_fx_pool = []
	if _fx_tpl != null and is_instance_valid(_fx_tpl):
		_fx_tpl.queue_free()
	_fx_tpl = null
	var fx = Rhythia.selected_hit_effect
	if Rhythia.show_hit_effect and fx != null and fx.path != "":
		var sc = load(fx.path)
		if sc is PackedScene:
			var inst = sc.instance()
			if inst is Spatial and inst.has_method("spawn"):
				if inst.has_method("setup"):
					inst.setup(fx.id, false)
				inst.visible = false
				add_child(inst)
				_fx_tpl = inst
				_fx_id = fx.id
			elif inst:
				inst.free()

# the note mesh as the song loads it (NoteManager._ready), with its materials
func _note_mesh(parts: Dictionary) -> Mesh:
	var nm = Rhythia.selected_mesh
	var mesh: Mesh = null
	if nm != null and ("user://" in nm.path or not nm.path.begins_with("res://")):
		mesh = ObjParse.load_obj(nm.path)
	elif nm != null:
		mesh = load(nm.path)
	if mesh == null or mesh.get_surface_count() == 0:
		mesh = load("res://assets/blocks/rounded.obj")
	mesh = mesh.duplicate()
	var solid = parts.get("./Game/Spawn:note_solid_mat")
	var trans = parts.get("./Game/Spawn:note_transparent_mat")
	if solid is Material:
		solid = solid.duplicate()
	if trans is Material:
		trans = trans.duplicate()
	var img = Globals.imageLoader.load_if_exists("user://note")
	if img:
		for m in [solid, trans]:
			if m is ShaderMaterial:
				m.set_shader_param("image", img)
				m.set_shader_param("use_image", true)
	if solid is Material:
		mesh.surface_set_material(0, solid)
	if mesh.get_surface_count() > 1 and trans is Material:
		mesh.surface_set_material(1, trans)
	if mesh.get_surface_count() > 2 and solid is Material:
		mesh.surface_set_material(2, solid)
	return mesh

static func _linstep(a: float, b: float, x: float) -> float:
	if a == b:
		return float(x >= a)
	return clamp((x - a) / (b - a), 0, 1)

# one frame: `shown` is [[cell (Vector2, -1..1), distance, colour, index], ...]
# far ones first; `cell` is where the cursor is; `hits` the notes hit since the
# last frame ([cell, colour])
func frame(delta: float, shown: Array, cell: Vector2, hits: Array, combo_col: Color):
	_check += delta
	if _check > 0.5:
		_check = 0.0
		if _signature() != _sig:
			_build()
	cam.fov = clamp(float(Rhythia.get("fov")), 1.0, 179.0)
	outer.visible = Rhythia.enable_border
	# camera and grid parallax / Spin (NoteManager.do_half_lock / do_spin)
	var co := Vector3(cell.x, cell.y, 0)
	var hlm := 0.25
	var hlpower: float = 0.1 * float(Rhythia.get("parallax"))
	var grm: float = float(Rhythia.get("grid_parallax")) * 0.1
	if Rhythia.spin_now():
		cam.transform = Transform(Basis(), Vector3(co.x * hlpower * hlm, co.y * hlpower * hlm, 3.5))
		cam.look_at(co, Vector3.UP)
		cam.transform.origin += cam.transform.basis.z / 4.0
	else:
		cam.transform = Transform(Basis(), Vector3(co.x * hlpower * hlm, co.y * hlpower * hlm, 3.75))
	spawn.transform.origin = Vector3(-(co.x * hlm * grm) - 1, -(co.y * hlm * grm) + 1, 0)
	# the notes
	var ar: float = max(0.1, float(Rhythia.get("approach_rate")))
	var sd: float = float(Rhythia.get("spawn_distance"))
	var fl: float = float(Rhythia.get("fade_length"))
	var op: float = float(Rhythia.note_opacity)
	var ghost: bool = bool(Rhythia.half_ghost)
	var gbase: float = clamp(float(Rhythia.half_ghost_strength), 0.1, 1.0)
	var nscale: float = 0.45 * float(Rhythia.note_size) * (float(Rhythia.note_hitbox_size) / 1.14)
	var spin: bool = Rhythia.note_spin_x != 0 or Rhythia.note_spin_y != 0 or Rhythia.note_spin_z != 0
	var mm: MultiMesh = notes.multimesh
	var n: int = int(min(shown.size(), MAX_NOTES))
	for i in range(n):
		var s: Array = shown[i]
		var dist: float = s[1]
		var alpha := op
		var fin := 1.0
		var fout := 1.0
		if fl != 0:
			fin = pow(_linstep(sd, sd * (1.0 - fl), dist), 1.3) * op
		if ghost:
			fout = ((1 - gbase) + pow(_linstep(3.0 / 50.0 * ar, 12.0 / 50.0 * ar, dist), 1.3) * gbase) * op
		if fl != 0 or ghost:
			alpha = min(fin, fout)
		var b := Basis().scaled(Vector3.ONE * nscale)
		if spin:
			# (the song turns each note a little every frame from when it shows)
			var age: float = (sd - dist) / ar * 60.0
			b = Basis().rotated(Vector3(1, 0, 0), Rhythia.note_spin_x / 2000.0 * age).rotated(Vector3(0, 1, 0), Rhythia.note_spin_y / 2000.0 * age).rotated(Vector3(0, 0, 1), Rhythia.note_spin_z / 2000.0 * age) * b
		var c: Vector2 = s[0]
		mm.set_instance_transform(i, Transform(b, Vector3(CURSOR_OFFSET.x + c.x, CURSOR_OFFSET.y + c.y, -dist)))
		var col: Color = s[2]
		mm.set_instance_color(i, Color(col.r, col.g, col.b, col.a * alpha))
	mm.visible_instance_count = n
	# the cursor
	cursor.transform.origin = CURSOR_OFFSET + co
	var cs: float = float(Rhythia.cursor_scale)
	if Rhythia.cursor_spin != 0:
		_spin_deg = fmod(_spin_deg - delta * Rhythia.cursor_spin, 360.0)
	var base_t = _song_parts().get("./Game/Spawn/Cursor/Mesh:transform")
	var bt: Transform = base_t if base_t is Transform else Transform()
	cursor_mesh.transform = Transform(bt.basis.rotated(Vector3(0, 0, 1), deg2rad(_spin_deg)).scaled(Vector3.ONE * cs), bt.origin)
	var m = cursor_mesh.get_surface_material(0)
	if m is SpatialMaterial:
		var ctype := int(Rhythia.cursor_color_type)
		if ctype == Globals.CURSOR_RAINBOW:
			m.albedo_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.65, 1)
		elif ctype == Globals.CURSOR_NOTE_COLOR:
			m.albedo_color = combo_col
		elif ctype == Globals.CURSOR_CUSTOM_COLOR:
			m.albedo_color = Rhythia.cursor_color # (it tints your cursor picture too, as in a song)
	# hit effects, where the song puts them (at the cursor, or on the note)
	if _fx_tpl != null and is_instance_valid(_fx_tpl):
		for h in hits:
			var at: Vector2 = cell if Rhythia.hit_effect_at_cursor else h[0]
			var pos: Vector3 = spawn.transform.xform(CURSOR_OFFSET + Vector3(at.x, at.y, 0))
			pos.z = 0.002
			var fx = null
			while not _fx_pool.empty() and fx == null:
				var c = _fx_pool.pop_back()
				if is_instance_valid(c):
					fx = c
			if fx == null:
				fx = _fx_tpl.duplicate()
				if "_pool" in fx:
					fx._pool = _fx_pool
			fx.spawn(self, pos, h[1], _fx_id, false)
