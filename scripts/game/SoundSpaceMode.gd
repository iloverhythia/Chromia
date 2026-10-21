extends Node

# Settings > Replays & Misc > Experimental > "Sound Space Mode": songs look like
# the classic (Roblox) Sound Space:
# - a dark navy tunnel with grid lines (assets/worlds/soundspace/tunnel.tscn)
# - corner brackets around the grid, with the time and a thin progress line at
#   the top and a green health line at the bottom inside them
# - dark see-through side panels in a pixel font: the multiplier box (its border
#   fills up towards the next multiplier), COMBO and accuracy on the left; score,
#   Misses and Notes on the right
# - the grey square cursor, and the points of each hit popping up under the
#   grid (notes keep your own mesh and colors)
#
# While a song plays, your display settings are set to how classic Sound Space
# looks (LOOK: FOV, no trail or effects...) and put back when the
# song ends (begin_song / end_song; a backup file covers a crash or quit).
# Your notes keep your own mesh and colors.
#
# HUD.gd adds this node (apply_hud); songload asks it for the background and
# calls begin_song.

const DIR := "res://assets/soundspace/"
const FONT := "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"
const SPACE := "res://assets/worlds/soundspace/tunnel.tscn"
# colors and sizes measured from a recording of classic Sound Space
const GREEN := Color(0.0, 0.98, 0.0)
const ACC_GREEN := Color(0.03, 0.84, 0.05)
const YELLOW := Color(0.98, 0.99, 0.02)
const ORANGE := Color(1.0, 0.55, 0.0)
const SCORE_YELLOW := Color(1.0, 0.95, 0.15)
const CYAN := Color(0.0, 1.0, 1.0)
const TIME_GREY := Color(0.6, 0.6, 0.63)
const PANEL := Color(0.0, 0.0, 0.0, 0.62)
const PANEL_SIZE := Vector2(420, 1000)
const PROGRESS_W := 690.0
const HEALTH_W := 620.0

var hud
var game
var _font_data: DynamicFontData
var _popup_font: DynamicFontData
var _max_since := -1.0 # seconds since x8 was reached (orange box, fading to yellow)
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

# Classic Sound Space's look, for the length of a song. Your camera (half-lock,
# spin, parallax, faraway HUD) is left as it is.
const LOOK := {
	"fov": 75.0, "hit_fov": false,
	"cursor_trail": false, "enable_drift_cursor": false, "follow_drift_cursor": false,
	"cursor_spin": 0.0, "cursor_face_velocity": false, "cursor_scale": 1.1,
	"show_hit_effect": false, "show_miss_effect": false, "note_spawn_effect": false,
	"note_visual_approach": false, "note_spin_x": 0.0, "note_spin_y": 0.0, "note_spin_z": 0.0,
	"glow": 0.0, "bloom": 0.0, "vhs_shader": false,
	"show_config": false, "simple_hud": false, "rainbow_hud": false,
	"attach_hp_to_grid": false, "attach_timer_to_grid": false, "expand_hud_onhr": false,
	"enable_grid": false, "enable_border": true, "show_left_panel": true,
	"show_right_panel": true, "show_timer": true, "show_hp_bar": true, "show_stats": false,
}
# a replay brings its own camera; those aren't touched while one plays
const REPLAY_KEYS := ["fov"]
const BACKUP_FILE := "user://.sound_space_backup.json"

static func begin_song():
	if not enabled() or Rhythia.has_meta("ss_backup"):
		return
	var backup := {}
	for k in LOOK:
		if Rhythia.replaying and REPLAY_KEYS.has(k):
			continue
		if not (k in Rhythia):
			continue
		backup[k] = Rhythia.get(k)
		Rhythia.set(k, LOOK[k])
	Rhythia.set_meta("ss_backup", backup)
	var f := File.new()
	if f.open(Globals.p(BACKUP_FILE), File.WRITE) == OK:
		f.store_string(var2str(backup))
		f.close()

static func end_song():
	if not Rhythia.has_meta("ss_backup"):
		return
	var backup: Dictionary = Rhythia.get_meta("ss_backup")
	for k in backup:
		Rhythia.set(k, backup[k])
	Rhythia.remove_meta("ss_backup")
	Directory.new().remove(Globals.p(BACKUP_FILE))

# At startup: a song didn't end normally last time (crash), so the settings
# saved then may be Sound Space's. Put yours back.
static func recover():
	var f := File.new()
	var path: String = Globals.p(BACKUP_FILE)
	if Rhythia.has_meta("ss_backup") or not f.file_exists(path):
		return
	if f.open(path, File.READ) != OK:
		return
	var backup = str2var(f.get_as_text())
	f.close()
	Directory.new().remove(path)
	if backup is Dictionary:
		for k in backup:
			if k in Rhythia:
				Rhythia.set(k, backup[k])
		Rhythia.save_settings()

static func enabled() -> bool:
	return bool(Rhythia.get("sound_space_mode"))

static func tex(name: String) -> Texture:
	return load(DIR + name + ".png") as Texture

# Background world path for songload.
static func space_path(default_path: String) -> String:
	return SPACE if enabled() else default_path

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

# A centered pixel-font label whose text is centered on `y`.
func _label(parent: Control, text: String, size: int, color: Color, y: float, w: float = 420.0) -> Label:
	var l := Label.new()
	l.add_font_override("font", _font(size))
	l.add_color_override("font_color", color)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.75))
	l.add_constant_override("shadow_offset_x", max(2, size / 10))
	l.add_constant_override("shadow_offset_y", max(2, size / 10))
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.rect_position = Vector2(0, y - size)
	l.rect_size = Vector2(w, size * 2)
	l.text = text
	parent.add_child(l)
	return l

# A side panel's viewport gets its own content (the stock panel is hidden).
func _panel_root(c: Control) -> Control:
	c.visible = false
	var root := ColorRect.new()
	root.name = "SoundSpace"
	root.color = PANEL
	root.rect_size = PANEL_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp: Viewport = c.get_parent()
	vp.size = PANEL_SIZE
	vp.add_child(root)
	# the 3D sprite showing it picks up the new size
	var spr = hud.get_node_or_null(vp.name.trim_suffix("VP") + "Hud")
	if spr is Sprite3D:
		spr.texture = vp.get_texture()
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
	_popup_font = load("res://assets/font/Lato/Lato-Bold.ttf")

	# left: multiplier box, COMBO, accuracy
	var left := _panel_root(hud.get_node("LeftVP/Control"))
	mult_box = MultBox.new()
	mult_box.rect_position = Vector2(65, 146)
	mult_box.rect_size = Vector2(290, 290)
	left.add_child(mult_box)
	mult_label = _label(left, "x1", 76, CYAN, 296)
	_label(left, "COMBO", 53, Color(1, 1, 1), 494)
	combo_label = _label(left, "0", 53, Color(1, 1, 1), 576)
	acc_label = _label(left, "100.00%", 58, ACC_GREEN, 658)

	# right: score, Misses, Notes
	var right := _panel_root(hud.get_node("RightVP/Control"))
	score_label = _label(right, "0", 36, SCORE_YELLOW, 204)
	_label(right, "Misses", 53, Color(1, 1, 1), 307)
	miss_label = _label(right, "0", 53, Color(1, 1, 1), 384)
	_label(right, "Notes", 53, Color(1, 1, 1), 499)
	notes_label = _label(right, "0/0", 53, Color(1, 1, 1), 576)

	# top (on the top bracket line): time, and a thin progress line under it
	var top := _bar_root(hud.get_node("TimerVP/Control"), "SoundSpace")
	time_label = _label(top, "0:00", 52, TIME_GREY, 127, 900)
	var line_bg := ColorRect.new()
	line_bg.color = Color(0.16, 0.15, 0.18)
	line_bg.rect_position = Vector2(450 - PROGRESS_W / 2, 172)
	line_bg.rect_size = Vector2(PROGRESS_W, 5)
	top.add_child(line_bg)
	progress_fill = ColorRect.new()
	progress_fill.color = Color(1, 1, 1)
	progress_fill.rect_position = Vector2(450 - PROGRESS_W / 2, 169)
	progress_fill.rect_size = Vector2(0, 11)
	top.add_child(progress_fill)

	# bottom (on the bottom bracket line): green health line
	var show_hp: bool = hud.energybar.visible
	var bottom := _bar_root(hud.get_node("EnergyVP/Control"), "SoundSpace")
	health_fill = ColorRect.new()
	health_fill.color = GREEN
	health_fill.rect_position = Vector2(450 - HEALTH_W / 2, 145)
	health_fill.rect_size = Vector2(HEALTH_W, 10)
	health_fill.visible = show_hp
	bottom.add_child(health_fill)
	var mods = hud.get_node_or_null("EnergyVP/Control/Modifiers")
	if mods:
		mods.rect_position.y += 150

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
		"EnergyHud": Vector3(0, -1.64, 0.05),
		"LeftHud": Vector3(-2.65, 0.24, 0.05),
		"RightHud": Vector3(2.65, 0.24, 0.05),
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
	var at: Vector3 = hud.to_global(Vector3(local.x, -1.25, 0))
	if cam.is_position_behind(at):
		return
	var p := cam.unproject_position(at)
	var vh := get_viewport().get_visible_rect().size.y
	var l := Label.new()
	var pf := DynamicFont.new()
	pf.font_data = _popup_font
	pf.size = int(max(10.0, vh / 720.0 * 17.0))
	l.add_font_override("font", pf)
	l.add_color_override("font_color", Color(0.62, 0.62, 0.66, 0.9))
	l.text = str(gained)
	l.rect_size = Vector2(200, 40)
	l.align = Label.ALIGN_CENTER
	l.rect_position = p - Vector2(100, 10)
	popups.add_child(l)
	var tw := Tween.new()
	l.add_child(tw)
	tw.interpolate_property(l, "rect_position:y", l.rect_position.y, l.rect_position.y - vh * 0.012, 0.6)
	tw.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.6, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.connect("tween_all_completed", l, "queue_free")
	tw.start()

func _process(delta):
	if not is_instance_valid(hud) or game == null:
		return
	mult_label.text = "x%d" % game.combo_level
	mult_box.progress = 1.0 if game.combo_level >= 8 else float(game.lvl_progress) / 10.0
	if game.combo_level >= 8:
		if _max_since < 0.0:
			_max_since = 0.0
		_max_since += delta
		mult_box.color = ORANGE.linear_interpolate(YELLOW, clamp((_max_since - 1.5) / 1.5, 0.0, 1.0))
	else:
		_max_since = -1.0
		mult_box.color = YELLOW
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
	progress_fill.rect_size.x = PROGRESS_W * prog
	var eb: ProgressBar = hud.energybar
	var hp := 0.0
	if eb.max_value > 0:
		hp = clamp(eb.value / eb.max_value, 0.0, 1.0)
	health_fill.rect_size.x = HEALTH_W * hp
	health_fill.rect_position.x = 450 - HEALTH_W * hp / 2.0

func _exit_tree():
	end_song()
	if _saved.has("hit"):
		Rhythia.hit_snd = _saved.hit
		Rhythia.miss_snd = _saved.miss
	if _saved.has("fail") and Rhythia.fail_asp != null:
		Rhythia.fail_asp.stream = _saved.fail

# The multiplier square: its border fills clockwise from the top-right corner
# towards the next multiplier.
class MultBox extends Control:
	var progress := 0.0
	var color := Color(0.98, 0.99, 0.02)
	const WIDTH := 14.0

	func _draw():
		var r := Rect2(Vector2(WIDTH / 2, WIDTH / 2), rect_size - Vector2(WIDTH, WIDTH))
		var pts := [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position, Vector2(r.end.x, r.position.y)]
		_path(pts, 1.0, Color(0.17, 0.17, 0.19))
		_path(pts, progress, color)

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
