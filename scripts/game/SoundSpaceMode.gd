extends Node

# Settings > Replays & Misc > Experimental > "Sound Space Mode": songs look like
# the classic (Roblox) Sound Space:
# - a dark navy tunnel with grid lines (assets/worlds/soundspace/tunnel.tscn)
# - corner brackets around the grid, with the time and a thin progress line at
#   the top and a green health line at the bottom inside them
# - dark see-through side panels in a pixel font: the multiplier box (its border
#   fills up towards the next multiplier), COMBO and accuracy on the left; score,
#   Misses and Notes on the right
# - hollow square notes, the grey square cursor, and the points of each hit
#   popping up under the grid
#
# HUD.gd adds this node (apply_hud); NoteManager and songload ask enabled() for
# the notes and the background. Your own settings stay as they are.

const DIR := "res://assets/soundspace/"
const FONT := "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"
const NOTE_MESH := "ssp_square"
const SPACE := "res://assets/worlds/soundspace/tunnel.tscn"
const GREEN := Color(0.13, 0.85, 0.13)
const YELLOW := Color(1.0, 0.92, 0.1)
const CYAN := Color(0.1, 0.9, 1.0)
const PANEL := Color(0.01, 0.01, 0.035, 0.82)
const BAR_W := 640.0

var hud
var game
var _font_data: DynamicFontData
var mult_box
var mult_label: Label
var combo_label: Label
var acc_label: Label
var score_label: Label
var miss_label: Label
var notes_label: Label
var time_label: Label
var progress_fill: ColorRect
var health_fill: ColorRect
var popups: CanvasLayer
var _last_score := 0
var _saved := {}

static func enabled() -> bool:
	return bool(Rhythia.get("sound_space_mode"))

static func tex(name: String) -> Texture:
	return load(DIR + name + ".png") as Texture

# Background world path for songload.
static func space_path(default_path: String) -> String:
	return SPACE if enabled() else default_path

# Note mesh for NoteManager.
static func note_mesh(default_mesh):
	if not enabled() or Rhythia.registry_mesh == null:
		return default_mesh
	var m = Rhythia.registry_mesh.get_item(NOTE_MESH)
	return m if m != null else default_mesh

static func apply_hud(h):
	if not enabled() or h.has_node("SoundSpaceMode"):
		return
	var n = load("res://scripts/game/SoundSpaceMode.gd").new()
	n.name = "SoundSpaceMode"
	n.hud = h
	h.add_child(n)
	n._build()

# ---------------------------------------------------------------------------

func _font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = _font_data
	f.size = size
	return f

func _label(parent: Control, text: String, size: int, color: Color, y: float, w: float = 300.0) -> Label:
	var l := Label.new()
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", color)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	l.add_constant_override("shadow_offset_x", 3)
	l.add_constant_override("shadow_offset_y", 3)
	l.align = Label.ALIGN_CENTER
	l.rect_position = Vector2(0, y)
	l.rect_size = Vector2(w, size * 1.4)
	l.text = text
	parent.add_child(l)
	return l

# A side panel's viewport gets its own content (the stock panel is hidden).
func _panel_root(c: Control) -> Control:
	c.visible = false
	var root := ColorRect.new()
	root.name = "SoundSpace"
	root.color = PANEL
	root.rect_size = Vector2(300, 900)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.get_parent().add_child(root)
	return root

func _bar_root(c: Control, name: String) -> Control:
	for ch in c.get_children():
		if ch is CanvasItem and ch.name != "Modifiers":
			ch.visible = false
	var root := Control.new()
	root.name = name
	root.rect_size = Vector2(900, 300)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(root)
	return root

func _build():
	pause_mode = PAUSE_MODE_PROCESS
	game = hud.Game
	_font_data = load(FONT)

	# left: multiplier box, COMBO, accuracy
	var left := _panel_root(hud.get_node("LeftVP/Control"))
	mult_box = MultBox.new()
	mult_box.rect_position = Vector2(55, 130)
	mult_box.rect_size = Vector2(190, 190)
	left.add_child(mult_box)
	mult_label = _label(left, "x1", 44, CYAN, 194)
	_label(left, "COMBO", 34, Color(1, 1, 1), 390)
	combo_label = _label(left, "0", 34, Color(1, 1, 1), 450)
	acc_label = _label(left, "100.00%", 30, GREEN, 515)

	# right: score, Misses, Notes
	var right := _panel_root(hud.get_node("RightVP/Control"))
	score_label = _label(right, "0", 22, YELLOW, 160)
	_label(right, "Misses", 34, Color(1, 1, 1), 230)
	miss_label = _label(right, "0", 34, Color(1, 1, 1), 285)
	_label(right, "Notes", 34, Color(1, 1, 1), 390)
	notes_label = _label(right, "0/0", 30, Color(1, 1, 1), 445)

	# top: time and a thin progress line
	var top := _bar_root(hud.get_node("TimerVP/Control"), "SoundSpace")
	time_label = _label(top, "0:00", 40, Color(0.62, 0.62, 0.68), 150, 900)
	var line_bg := ColorRect.new()
	line_bg.color = Color(0.25, 0.25, 0.3, 0.8)
	line_bg.rect_position = Vector2(450 - BAR_W / 2, 232)
	line_bg.rect_size = Vector2(BAR_W, 4)
	top.add_child(line_bg)
	progress_fill = ColorRect.new()
	progress_fill.color = Color(1, 1, 1)
	progress_fill.rect_position = Vector2(450 - BAR_W / 2, 228)
	progress_fill.rect_size = Vector2(0, 10)
	top.add_child(progress_fill)

	# bottom: green health line
	var show_hp: bool = hud.energybar.visible
	var bottom := _bar_root(hud.get_node("EnergyVP/Control"), "SoundSpace")
	health_fill = ColorRect.new()
	health_fill.color = GREEN
	health_fill.rect_position = Vector2(450 - BAR_W / 2, 14)
	health_fill.rect_size = Vector2(BAR_W, 10)
	health_fill.visible = show_hp
	bottom.add_child(health_fill)

	var combo = hud.get_node_or_null("ComboHud")
	if combo:
		combo.visible = false

	# points of each hit pop up under the grid
	popups = CanvasLayer.new()
	popups.layer = 1
	add_child(popups)
	_last_score = game.score
	game.connect("hit", self, "_on_hit")

	_place_hud()

	# sounds for this song only
	_saved = {"hit": Rhythia.hit_snd, "miss": Rhythia.miss_snd}
	Rhythia.hit_snd = load(DIR + "hit.mp3")
	Rhythia.miss_snd = load(DIR + "miss.mp3")
	if Rhythia.fail_asp != null:
		_saved["fail"] = Rhythia.fail_asp.stream
		Rhythia.fail_asp.stream = load(DIR + "fail.mp3")
	# the cursor and grid are set up after this (they're further down the scene)
	call_deferred("_apply_3d")

# Panels flat towards the player, side panels just outside the brackets, the
# time and health inside them.
func _place_hud():
	var flat := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	var spots := {
		"TimerHud": Vector3(0, 1.6, 0.05),
		"EnergyHud": Vector3(0, -2.1, 0.05),
		"LeftHud": Vector3(-2.75, 0, 0.05),
		"RightHud": Vector3(2.75, 0, 0.05),
	}
	for n in spots:
		var s = hud.get_node_or_null(n)
		if s == null:
			continue # moved onto the grid (attach to grid settings)
		s.transform = Transform(flat, spots[n])

func _apply_3d():
	if not is_instance_valid(hud):
		return
	var spawn = hud.Spawn
	var outer = spawn.get_node_or_null("Outer")
	if outer:
		var m: SpatialMaterial = outer.get("material/0").duplicate()
		outer.set("material/0", m)
		m.albedo_texture = tex("grid")
		m.albedo_color = Color(1, 1, 1, 1)
		outer.scale *= 1.45
	var cm = spawn.get_node_or_null("Cursor/Mesh")
	if cm:
		var mat: SpatialMaterial = cm.get("material/0").duplicate()
		cm.set("material/0", mat)
		mat.albedo_texture = tex("cursor")
		mat.albedo_color = Color(1, 1, 1, 1)

func _on_hit(_col = null):
	var gained: int = game.score - _last_score
	_last_score = game.score
	if gained <= 0:
		return
	var cam := get_viewport().get_camera()
	var cursor = hud.Spawn.get_node_or_null("Cursor")
	if cam == null or cursor == null:
		return
	var local: Vector3 = hud.to_local(cursor.global_transform.origin)
	var at: Vector3 = hud.to_global(Vector3(local.x, -1.62, 0))
	if cam.is_position_behind(at):
		return
	var p := cam.unproject_position(at)
	var vh := get_viewport().get_visible_rect().size.y
	var l := Label.new()
	l.add_font_override("font", _font(int(max(10.0, vh / 1080.0 * 22.0))))
	l.add_color_override("font_color", Color(0.85, 0.85, 0.9))
	l.text = str(gained)
	l.rect_size = Vector2(200, 40)
	l.align = Label.ALIGN_CENTER
	l.rect_position = p - Vector2(100, 10)
	popups.add_child(l)
	var tw := Tween.new()
	l.add_child(tw)
	tw.interpolate_property(l, "rect_position:y", l.rect_position.y, l.rect_position.y + vh * 0.02, 0.7)
	tw.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.7, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.connect("tween_all_completed", l, "queue_free")
	tw.start()

func _process(_d):
	if not is_instance_valid(hud) or game == null:
		return
	mult_label.text = "x%d" % game.combo_level
	mult_box.level = game.combo_level
	mult_box.progress = 1.0 if game.combo_level >= 8 else float(game.lvl_progress) / 10.0
	mult_box.update()
	combo_label.text = Globals.comma_sep(game.combo)
	var total: int = game.total_notes
	var acc: float = 100.0 if total <= 0 else 100.0 * float(game.hits) / float(total)
	acc_label.text = "%.2f%%" % acc
	score_label.text = Globals.comma_sep(game.score)
	miss_label.text = Globals.comma_sep(game.misses)
	notes_label.text = "%s/%s" % [Globals.comma_sep(game.hits), Globals.comma_sep(total)]
	var ms: float = max(0.0, hud.Spawn.ms)
	var s := int(ms / 1000.0)
	time_label.text = "%d:%02d" % [s / 60, s % 60]
	var tb: ProgressBar = hud.timebar
	var prog := 0.0
	if tb.max_value > tb.min_value:
		prog = clamp((tb.value - tb.min_value) / (tb.max_value - tb.min_value), 0.0, 1.0)
	progress_fill.rect_size.x = BAR_W * prog
	var eb: ProgressBar = hud.energybar
	var hp := 0.0
	if eb.max_value > 0:
		hp = clamp(eb.value / eb.max_value, 0.0, 1.0)
	health_fill.rect_size.x = BAR_W * hp
	health_fill.rect_position.x = 450 - BAR_W * hp / 2.0

func _exit_tree():
	if _saved.has("hit"):
		Rhythia.hit_snd = _saved.hit
		Rhythia.miss_snd = _saved.miss
	if _saved.has("fail") and Rhythia.fail_asp != null:
		Rhythia.fail_asp.stream = _saved.fail

# The multiplier square: its border fills clockwise towards the next multiplier.
class MultBox extends Control:
	var progress := 0.0
	var level := 1
	const WIDTH := 10.0

	func _draw():
		var r := Rect2(Vector2(WIDTH / 2, WIDTH / 2), rect_size - Vector2(WIDTH, WIDTH))
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
		_path(pts, 1.0, Color(0.18, 0.18, 0.2))
		var col: Color = Color(1.0, 0.92, 0.1) if level < 8 else Color(1.0, 0.6, 0.05)
		_path(pts, progress, col)

	func _path(pts: Array, amount: float, col: Color):
		var total := 0.0
		for i in range(1, pts.size()):
			total += pts[i - 1].distance_to(pts[i])
		var left := total * clamp(amount, 0.0, 1.0)
		for i in range(1, pts.size()):
			if left <= 0.0:
				break
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var d := a.distance_to(b)
			var t: float = min(1.0, left / d)
			var e := a.linear_interpolate(b, t)
			# square ends so the corners meet
			var dir := (b - a).normalized()
			draw_line(a - dir * WIDTH / 2, e + dir * (WIDTH / 2 if t >= 1.0 else 0.0), col, WIDTH)
			left -= d
