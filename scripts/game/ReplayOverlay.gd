extends Spatial

# The replay viewer's drawings on the grid, switched by the buttons on its bar
# (ReplayControls.gd; Rhythia.replay_cursor_path / replay_note_hitbox /
# replay_frame_marker, kept in the settings):
#
#   Cursor Path     the line the cursor took: the last PAST_MS behind it,
#                   fading out, and the next AHEAD_MS in front of it, dimmer
#   Frame Markers   a dot on every position the replay recorded in that
#                   stretch (the cursor is drawn in a straight line between
#                   them: this shows how many there are and where)
#   Note Hitboxes   the square a note is hit in (the cursor's middle has to be
#                   inside it): a white square that comes in with each note,
#                   on its near side
#
# A child of the note area (NoteManager), so everything is in its own units:
# the cursor's and the notes' positions as the game itself places them.

const AHEAD_MAX_MS := 350.0
const MAX_BOXES := 160
const FRONT := 0.12 # how far in front of its note a hitbox square is drawn

var spawn # NoteManager
var cursor: Spatial
var _lines: ImmediateGeometry
var _dots: ImmediateGeometry
var _boxes: ImmediateGeometry
var _was := false
var _col := Color(1, 0.756863, 0.960784) # the menus' accent (your Menu Customizer look's)

func setup(spawn_node, cursor_node: Spatial):
	spawn = spawn_node
	cursor = cursor_node

static func _material(points: bool) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.vertex_color_use_as_albedo = true
	m.flags_no_depth_test = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.render_priority = 20
	if points:
		m.flags_use_point_size = true
		m.params_point_size = 4.0
	return m

func _ready():
	# (after the note area has moved its notes for this frame: its own
	# process_priority is 2. Before it, the squares were a frame behind their notes)
	process_priority = 3
	_col = load("res://scripts/ui/menu/OnlineStyle.gd").new().ACCENT
	_lines = ImmediateGeometry.new()
	_lines.material_override = _material(false)
	_lines.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_dots = ImmediateGeometry.new()
	_dots.material_override = _material(true)
	_dots.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)
	_boxes = ImmediateGeometry.new()
	_boxes.material_override = _material(false)
	_boxes.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(_boxes)

# a recorded position as the cursor is placed for it (Cursor.gd)
func _place(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y if Rhythia.replay.sv < 3 else -y, z)

# index of the last sample at or before t (-1: none)
static func _last_before(list: Array, t: float) -> int:
	var lo := 0
	var hi := list.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if list[mid].z <= t:
			lo = mid + 1
		else:
			hi = mid
	return lo - 1

func _process(_d):
	var path: bool = Rhythia.replay_cursor_path
	var marks: bool = Rhythia.replay_frame_marker
	var boxes: bool = Rhythia.replay_note_hitbox
	var any: bool = (path or marks or boxes) and Rhythia.replaying and Rhythia.replay != null and spawn != null and is_instance_valid(spawn)
	if not any:
		if _was:
			_was = false
			_lines.clear()
			_dots.clear()
			_boxes.clear()
		return
	_was = true
	_lines.clear()
	_dots.clear()
	_boxes.clear()
	var z: float = cursor.transform.origin.z if cursor != null and is_instance_valid(cursor) else 0.0
	var col: Color = _col
	var list: Array = Rhythia.replay.cursor_positions
	var now: float = spawn.rms
	# how far back (the bar's Length slider) and ahead (a share of it, up to 350 ms)
	var PAST_MS: float = clamp(float(Rhythia.replay_cursor_path_ms), 100.0, 5000.0)
	var AHEAD_MS: float = min(AHEAD_MAX_MS, PAST_MS * 0.4)
	if (path or marks) and list.size() >= 2:
		var a := int(max(0, _last_before(list, now - PAST_MS)))
		var b := int(min(list.size() - 1, _last_before(list, now + AHEAD_MS) + 1))
		if b > a:
			if path:
				_lines.begin(Mesh.PRIMITIVE_LINE_STRIP)
				for i in range(a, b + 1):
					var s: Vector3 = list[i]
					var t: float = s.z - now
					var alpha: float = (1.0 - clamp(-t / PAST_MS, 0.0, 1.0)) * 0.9 if t <= 0.0 else (1.0 - clamp(t / AHEAD_MS, 0.0, 1.0)) * 0.35
					_lines.set_color(Color(col.r, col.g, col.b, alpha))
					_lines.add_vertex(_place(s.x, s.y, z))
				_lines.end()
			if marks:
				_dots.begin(Mesh.PRIMITIVE_POINTS)
				for i in range(a, b + 1):
					var s2: Vector3 = list[i]
					var t2: float = s2.z - now
					var alpha2: float = (1.0 - clamp(-t2 / PAST_MS, 0.0, 1.0)) if t2 <= 0.0 else (1.0 - clamp(t2 / AHEAD_MS, 0.0, 1.0)) * 0.5
					_dots.set_color(Color(1, 1, 1, max(alpha2, 0.08)))
					_dots.add_vertex(_place(s2.x, s2.y, z))
				_dots.end()
	if boxes:
		_draw_boxes(z)

# A white square the size of the note's hitbox, travelling with each note on
# its near side (towards you), from where the note appears until it is hit or
# gone. Fainter far away, solid as it arrives. (It used to be squares lying
# on the grid for the next 48 notes at once, green or red: a note's hit state
# was read as its time, so none of them waited for its note.)
func _draw_boxes(_z: float):
	var notes: Array = spawn.notes
	if notes.empty():
		return
	var hbs: float = Rhythia.note_hitbox_size / 2
	if hbs == 0.57: hbs = 0.56875
	if Rhythia.mod_hard_mode:
		hbs *= Rhythia.HARD_MODE_SCALE
	var draw_ms: float = float(spawn.get("_draw_ms")) if spawn.get("_draw_ms") != null else float(spawn.ms)
	var per_ms: float = float(spawn.get("_f_approach_speed")) / 1000.0 if spawn.get("_f_approach_speed") != null else 0.0
	var far: float = float(spawn.get("_f_spawn_dist")) if spawn.get("_f_spawn_dist") != null else 0.0
	if per_ms <= 0.0 or far <= 0.0:
		return
	var back: float = float(spawn.get("grid_pushback")) if spawn.get("grid_pushback") != null else 0.0
	var w: float = max(0.03, hbs * 0.075) # the outline's width
	var from: int = int(clamp(int(spawn.current_note), 0, notes.size() - 1))
	var began := false
	var drawn := 0
	for i in range(from, notes.size()):
		var nd: Array = notes[i]
		var dist: float = per_ms * (float(nd[1]) - draw_ms)
		if dist > far or drawn >= MAX_BOXES:
			break
		if int(nd[2]) != Globals.NSTATE_ACTIVE or dist < -back - 0.01:
			continue
		var p: Vector2 = nd[0]
		# (a note that goes on past the grid, Note Pushback: its square waits on
		# the grid, where it is hit, and doesn't fly into the camera)
		var z: float = -max(dist, 0.0) + FRONT
		var c := Color(1, 1, 1, 0.3 + 0.7 * (1.0 - clamp(dist / far, 0.0, 1.0)))
		if not began:
			began = true
			_boxes.begin(Mesh.PRIMITIVE_TRIANGLES)
		# four bars: top, bottom, left, right (outer edge = the hitbox)
		_bar(p.x - hbs, p.y + hbs - w, p.x + hbs, p.y + hbs, z, c)
		_bar(p.x - hbs, p.y - hbs, p.x + hbs, p.y - hbs + w, z, c)
		_bar(p.x - hbs, p.y - hbs + w, p.x - hbs + w, p.y + hbs - w, z, c)
		_bar(p.x + hbs - w, p.y - hbs + w, p.x + hbs, p.y + hbs - w, z, c)
		drawn += 1
	if began:
		_boxes.end()

func _bar(x0: float, y0: float, x1: float, y1: float, z: float, c: Color):
	for v in [Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)]:
		_boxes.set_color(c)
		_boxes.add_vertex(v)
