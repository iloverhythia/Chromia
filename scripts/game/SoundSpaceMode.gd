extends Node

# Settings > Replays & Misc > Experimental > "Sound Space Mode": songs look like
# the original Sound Space (from the SSLookalike skin, assets/soundspace):
# grey side panels with the hits and misses, a thin green health bar under the
# grid and a white progress bar over it, corner brackets around the grid, the
# grey square cursor, rounded notes, the Void background, a grey circle where a
# note was missed, and the skin's hit / miss / fail sounds.
#
# HUD.gd adds this node (apply_hud); NoteManager, songload and Game ask
# enabled() for the rest. Your own settings are left as they are: the sounds
# are only swapped while the song runs.

const DIR := "res://assets/soundspace/"
const ACCENT := Color("c90045")
const NOTE_MESH := "ssp_rounded"
const SPACE := "furria_space_void"

var hud
var hits_label: Label
var miss_label: Label
var health: TextureProgress
var progress: TextureProgress
var _saved := {}

static func enabled() -> bool:
	return bool(Rhythia.get("sound_space_mode"))

static func tex(name: String) -> Texture:
	return load(DIR + name + ".png") as Texture

# Background world path for songload.
static func space_path(default_path: String) -> String:
	if not enabled() or Rhythia.registry_world == null:
		return default_path
	var w = Rhythia.registry_world.get_item(SPACE)
	return w.path if w != null else default_path

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

# A grey circle where a note was missed (NoteManager).
static func miss_marker(parent: Spatial, pos: Vector3):
	var s := Sprite3D.new()
	s.texture = tex("miss_feedback")
	s.pixel_size = 0.9 / 512.0
	s.transform.origin = Vector3(pos.x, pos.y, 0.003)
	s.modulate = Color(1, 1, 1, 0.85)
	s.render_priority = 50
	parent.add_child(s)
	var tw := Tween.new()
	s.add_child(tw)
	tw.interpolate_property(s, "modulate:a", 0.85, 0.0, 0.45, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.interpolate_property(s, "scale", Vector3.ONE, Vector3.ONE * 1.15, 0.45)
	tw.connect("tween_all_completed", s, "queue_free")
	tw.start()

# ---------------------------------------------------------------------------

func _build():
	pause_mode = PAUSE_MODE_PROCESS
	var bold := DynamicFont.new()
	bold.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	bold.size = 96
	bold.use_filter = true
	hits_label = _panel(hud.get_node("LeftVP/Control"), "panel_left_background", "hits", bold)
	miss_label = _panel(hud.get_node("RightVP/Control"), "panel_right_background", "misses", bold)

	# health under the grid
	var ec: Control = hud.get_node("EnergyVP/Control")
	var show_hp: bool = hud.energybar.visible
	hud.energybar.visible = false
	health = _bar(ec, "health_background", "health", 22.0)
	health.visible = show_hp
	# progress over the grid
	var tc: Control = hud.get_node("TimerVP/Control")
	for c in tc.get_children():
		if c is CanvasItem:
			c.visible = false
	progress = _bar(tc, "progress_background", "progress", 262.0)

	# no combo number over the grid
	var combo = hud.get_node_or_null("ComboHud")
	if combo:
		combo.visible = false

	# sounds for this song only
	_saved = {"hit": Rhythia.hit_snd, "miss": Rhythia.miss_snd}
	Rhythia.hit_snd = load(DIR + "hit.mp3")
	Rhythia.miss_snd = load(DIR + "miss.mp3")
	if Rhythia.fail_asp != null:
		_saved["fail"] = Rhythia.fail_asp.stream
		Rhythia.fail_asp.stream = load(DIR + "fail.mp3")
	# the cursor and grid are set up after this (they're further down the scene)
	call_deferred("_apply_3d")

# Hides a side panel and puts the Sound Space panel, icon and a counter in
# its viewport instead; returns the counter.
func _panel(c: Control, bg: String, icon: String, font: Font) -> Label:
	c.visible = false
	var size := Vector2(300, 900)
	var root := Control.new()
	root.name = "SoundSpace"
	root.rect_size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.get_parent().add_child(root)
	var back := TextureRect.new()
	back.texture = tex(bg)
	back.expand = true
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.rect_size = size
	back.modulate = Color(1, 1, 1, 0.9)
	root.add_child(back)
	var ic := TextureRect.new()
	ic.texture = tex(icon)
	ic.expand = true
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.rect_position = Vector2(60, 250)
	ic.rect_size = Vector2(180, 180)
	root.add_child(ic)
	var l := Label.new()
	l.add_font_override("font", font)
	l.add_color_override("font_color", Color(1, 1, 1))
	l.align = Label.ALIGN_CENTER
	l.rect_position = Vector2(0, 450)
	l.rect_size = Vector2(300, 120)
	l.text = "0"
	root.add_child(l)
	return l

func _bar(parent: Control, under: String, fill: String, center_y: float) -> TextureProgress:
	var b := TextureProgress.new()
	b.texture_under = tex(under)
	b.texture_progress = tex(fill)
	b.nine_patch_stretch = true
	b.rect_size = Vector2(800, 800.0 * 80.0 / 1088.0)
	b.rect_position = Vector2(50, center_y - b.rect_size.y / 2.0)
	b.max_value = 1.0
	b.step = 0.0
	b.value = 1.0
	parent.add_child(b)
	return b

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
	var cm = spawn.get_node_or_null("Cursor/Mesh")
	if cm:
		var mat: SpatialMaterial = cm.get("material/0").duplicate()
		cm.set("material/0", mat)
		mat.albedo_texture = tex("cursor")
		mat.albedo_color = Color(1, 1, 1, 1)

func _process(_d):
	if not is_instance_valid(hud):
		return
	var g = hud.Game
	hits_label.text = Globals.comma_sep(g.hits)
	miss_label.text = Globals.comma_sep(g.misses)
	var eb: ProgressBar = hud.energybar
	health.value = eb.value / eb.max_value if eb.max_value > 0 else 0.0
	var tb: ProgressBar = hud.timebar
	progress.value = (tb.value - tb.min_value) / (tb.max_value - tb.min_value) if tb.max_value > tb.min_value else 0.0

func _exit_tree():
	if _saved.has("hit"):
		Rhythia.hit_snd = _saved.hit
		Rhythia.miss_snd = _saved.miss
	if _saved.has("fail") and Rhythia.fail_asp != null:
		Rhythia.fail_asp.stream = _saved.fail
