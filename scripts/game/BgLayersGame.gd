extends CanvasLayer

# Draws the Background Editor layers during gameplay.
#
# Godot 3 always draws 2D canvas layers on top of the 3D scene, unless the
# world's Environment uses background_mode = BG_CANVAS, in which case canvas
# layers up to background_canvas_max_layer become the background.
#
# - "front" (default): layer -1, above the 3D world but below every other 2D
#   element of the song scene (fade, flashlight, pause/results UI).
# - "behind": only for worlds whose background is a plain colour. The
#   Environment is switched to BG_CANVAS and our layer (with a ColorRect of the
#   world's colour underneath) becomes the background, so the world's 3D
#   objects and the notes draw over the layers. Sky worlds can't do that, so
#   they fall back to "front". The Environment is restored when the song ends
#   (the world scene is cached and reused).

const BG = preload("res://scripts/BgLayers.gd")
const BEHIND_LAYER = -100

var _layers: Array = []
var _rects: Array = []
var _root: Control
var _env: Environment = null
var _old_mode: int = 0
var _old_max_layer: int = 0
var _fill: ColorRect = null
var _videos: Array = []

func _ready():
	pause_mode = PAUSE_MODE_INHERIT
	layer = -1
	var d = BG.load_data()
	if not d.enabled:
		queue_free()
		return
	_root = Control.new()
	_root.name = "Layers"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for l in d.layers:
		if l.opacity <= 0.001:
			continue
		var v = BG.build_visual(l, _root, null, false)
		if v.ok:
			_layers.append(l)
			_rects.append(v.rect)
			if v.video != null:
				_videos.append(v.video)
		else:
			v.rect.queue_free()
	if _rects.empty():
		queue_free()
		return
	get_viewport().connect("size_changed", self, "_layout")
	_layout()
	set_process(false)
	if not _videos.empty():
		call_deferred("_start_videos")
	if d.placement == BG.PLACE_BEHIND:
		# The world is added with call_deferred by Game.gd, so look for it after.
		call_deferred("_setup_behind")

func _layout():
	if _root == null or not is_instance_valid(_root):
		return
	var screen = get_viewport().get_visible_rect().size
	_root.rect_position = Vector2()
	_root.rect_size = screen
	if _fill != null and is_instance_valid(_fill):
		_fill.rect_size = screen
	for i in _rects.size():
		BG.apply_visual(_rects[i], _layers[i], screen)

# Started after the song scene is set up (Game.gd pauses the tree in _ready).
func _start_videos():
	yield(get_tree(), "idle_frame")
	for v in _videos:
		if is_instance_valid(v) and v.is_inside_tree() and not v.is_playing():
			v.play()

func _find_env(n: Node):
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var r = _find_env(c)
		if r != null:
			return r
	return null

func _setup_behind():
	if not is_inside_tree():
		return
	if get_viewport().transparent_bg:
		return # see-through world: a filled background would hide the desktop
	var song = get_parent().get_parent() if get_parent() != null else null
	if song == null:
		return
	var space = song.get_node_or_null("Space")
	if space == null:
		return
	var we = _find_env(space)
	if we == null or we.environment == null:
		return
	var env: Environment = we.environment
	if env.background_mode != Environment.BG_COLOR and env.background_mode != Environment.BG_CLEAR_COLOR:
		return # sky etc.: stay in front
	_env = env
	_old_mode = env.background_mode
	_old_max_layer = env.background_canvas_max_layer
	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.color = _bg_color()
	_root.add_child(_fill)
	_root.move_child(_fill, 0)
	layer = BEHIND_LAYER
	env.background_canvas_max_layer = BEHIND_LAYER
	env.background_mode = Environment.BG_CANVAS
	# Sub-viewports (the HUD panels' text) share the world's Environment. In
	# BG_CANVAS mode they would draw the "canvas background" into themselves
	# and smear; they only draw 2D, so their environment is turned off.
	_disable_sub_viewport_env(song)
	if not get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().connect("node_added", self, "_on_node_added")
	_layout()
	set_process(true) # some worlds change their background colour while playing

func _disable_sub_viewport_env(n: Node):
	if n is Viewport:
		_disable_env(n)
	for c in n.get_children():
		_disable_sub_viewport_env(c)

func _disable_env(vp: Viewport):
	if vp == get_tree().root or not is_instance_valid(vp):
		return
	if vp.own_world or vp.world != null:
		return # has its own World, not affected
	if vp.usage != Viewport.USAGE_2D and vp.usage != Viewport.USAGE_2D_NO_SAMPLING:
		return # may render 3D: leave it alone
	VisualServer.viewport_set_disable_environment(vp.get_viewport_rid(), true)

func _on_node_added(n: Node):
	if _env != null and n is Viewport:
		_disable_env(n)

func _bg_color() -> Color:
	var c: Color
	if _old_mode == Environment.BG_COLOR and _env != null:
		c = _env.background_color
	else:
		c = ProjectSettings.get_setting("rendering/environment/default_clear_color")
	c.a = 1.0
	return c

func _process(_delta):
	if _fill == null or _env == null:
		set_process(false)
		return
	var c = _env.background_color
	if _old_mode == Environment.BG_COLOR and c != _fill.color:
		c.a = 1.0
		_fill.color = c

func _exit_tree():
	if get_tree() != null and get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().disconnect("node_added", self, "_on_node_added")
	if _env != null:
		_env.background_mode = _old_mode
		_env.background_canvas_max_layer = _old_max_layer
		_env = null
