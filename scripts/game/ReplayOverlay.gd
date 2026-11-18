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
#                   inside it), for the notes about to arrive and just gone:
#                   white while it comes, green once the replay hit it, red
#                   when it missed
#
# A child of the note area (NoteManager), so everything is in its own units:
# the cursor's and the notes' positions as the game itself places them.

const PAST_MS := 900.0
const AHEAD_MS := 350.0
const BOX_AHEAD_MS := 550.0
const BOX_PAST_MS := 160.0
const MAX_BOXES := 48

var spawn # NoteManager
var cursor: Spatial
var _lines: ImmediateGeometry
var _dots: ImmediateGeometry
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
	_col = load("res://scripts/ui/menu/OnlineStyle.gd").new().ACCENT
	_lines = ImmediateGeometry.new()
	_lines.material_override = _material(false)
	_lines.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	_dots = ImmediateGeometry.new()
	_dots.material_override = _material(true)
	_dots.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)

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
		return
	_was = true
	_lines.clear()
	_dots.clear()
	var z: float = cursor.transform.origin.z if cursor != null and is_instance_valid(cursor) else 0.0
	var col: Color = _col
	var list: Array = Rhythia.replay.cursor_positions
	var now: float = spawn.rms
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

func _draw_boxes(z: float):
	var notes: Array = spawn.notes
	if notes.empty():
		return
	var hbs: float = Rhythia.note_hitbox_size / 2
	if hbs == 0.57: hbs = 0.56875
	if Rhythia.mod_hard_mode:
		hbs *= Rhythia.HARD_MODE_SCALE
	var ms: float = spawn.ms
	var speed: float = max(0.05, float(spawn.get("speed_multi")) if spawn.get("speed_multi") != null else 1.0)
	var from: int = int(clamp(int(spawn.current_note), 0, notes.size() - 1))
	# (a few that just went by, to see how they ended)
	var first := from
	while first > 0 and float(notes[first - 1][2]) >= ms - BOX_PAST_MS * speed and from - first < 8:
		first -= 1
	var began := false
	var drawn := 0
	for i in range(first, notes.size()):
		var nt: float = float(notes[i][2])
		if nt > ms + BOX_AHEAD_MS * speed or drawn >= MAX_BOXES:
			break
		var p: Vector2 = notes[i][0]
		var c := Color(1, 1, 1, 0.25 + 0.6 * (1.0 - clamp((nt - ms) / (BOX_AHEAD_MS * speed), 0.0, 1.0)))
		if nt <= ms:
			# gone by: how the replay ended it
			var hit: bool = Rhythia.replay.sv != 1 and Rhythia.replay.should_hit(i)
			c = Color(0.45, 1.0, 0.55, 0.9) if hit else Color(1.0, 0.4, 0.4, 0.9)
		if not began:
			began = true
			_lines.begin(Mesh.PRIMITIVE_LINES)
		var corners := [Vector3(p.x - hbs, p.y - hbs, z), Vector3(p.x + hbs, p.y - hbs, z), Vector3(p.x + hbs, p.y + hbs, z), Vector3(p.x - hbs, p.y + hbs, z)]
		for k in 4:
			_lines.set_color(c)
			_lines.add_vertex(corners[k])
			_lines.set_color(c)
			_lines.add_vertex(corners[(k + 1) % 4])
		drawn += 1
	if began:
		_lines.end()
