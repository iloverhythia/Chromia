extends Node
# Player #7: on the menu, a video over everything. Always the first time this
# is in their game, then one start in five. Esc or a click closes it after a
# few seconds. (Not on VR, never during a song.)

const VIDEO := "res://assets/video/b5.ogv"
const SEEN := "user://.menu_extras"
const NUMBER := 7
const SKIP_AFTER := 3.0

var _checked := false
var _t := 0.0
var _layer: CanvasLayer = null
var _player: VideoPlayer = null
var _shown := 0.0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func _process(delta):
	if _layer != null:
		_shown += delta
		_fit()
		return
	if _checked:
		set_process(false)
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var lm = get_node_or_null("/root/LobbyManager")
	if lm == null or int(lm.my_player_number) <= 0:
		return # (not known yet: online once connected)
	if int(lm.my_player_number) != NUMBER:
		_checked = true
		return
	var scene = get_tree().current_scene
	if scene == null or scene.name != "Menu" or Rhythia.vr:
		return
	_checked = true
	var f := File.new()
	if not f.file_exists(SEEN):
		if f.open(SEEN, File.WRITE) == OK:
			f.store_string("1")
			f.close()
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		if rng.randi_range(1, 5) != 1:
			return
	_play()

func _play():
	var stream = load(VIDEO)
	if stream == null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 127
	add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.connect("gui_input", self, "_on_input")
	_layer.add_child(bg)
	_player = VideoPlayer.new()
	_player.stream = stream
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.connect("finished", self, "_close")
	_layer.add_child(_player)
	_fit()
	_player.play()

# the video as big as fits, in the middle (it's taller than it is wide)
func _fit():
	if _player == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tex = _player.get_video_texture()
	var vs := Vector2(432, 768)
	if tex != null and tex.get_width() > 0:
		vs = Vector2(tex.get_width(), tex.get_height())
	var k: float = min(vp.x / vs.x, vp.y / vs.y)
	_player.rect_size = (vs * k).floor()
	_player.rect_position = ((vp - _player.rect_size) / 2).floor()

func _on_input(e):
	if e is InputEventMouseButton and e.pressed and _shown >= SKIP_AFTER:
		_close()

func _unhandled_input(e):
	if _layer != null and e is InputEventKey and e.pressed and e.scancode == KEY_ESCAPE and _shown >= SKIP_AFTER:
		get_tree().set_input_as_handled()
		_close()

func _close():
	if _layer != null:
		_layer.queue_free()
	_layer = null
	_player = null
	set_process(false)
