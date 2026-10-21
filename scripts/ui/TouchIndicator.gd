extends CanvasLayer

# Phones/tablets: a ring under each finger touching the screen (menus and
# songs), fading out when the finger lifts. Settings > Gameplay > Touch
# Indicator turns it off. A picture saved as "touch" in the user folder
# replaces the ring.

const SIZE := 46.0        # ring diameter, in layout pixels
const FADE_SEC := 0.18

var _touches := {}        # finger index -> {pos, alpha, down}
var _canvas: Control
var _custom: Texture = null

func _ready():
	layer = 128 # above everything, notifications included
	pause_mode = PAUSE_MODE_PROCESS
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.anchor_right = 1.0
	_canvas.anchor_bottom = 1.0
	_canvas.connect("draw", self, "_draw_touches")
	add_child(_canvas)
	_custom = Globals.imageLoader.load_if_exists("user://touch")

func _input(event):
	if not Rhythia.show_touch_indicator:
		if not _touches.empty():
			_touches.clear()
			_canvas.update()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = {pos = event.position, alpha = 1.0, down = true}
		elif _touches.has(event.index):
			_touches[event.index].pos = event.position
			_touches[event.index].down = false
		_canvas.update()
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index].pos = event.position
		else:
			_touches[event.index] = {pos = event.position, alpha = 1.0, down = true}
		_canvas.update()

func _process(delta):
	if _touches.empty():
		return
	var gone := []
	for i in _touches:
		var t: Dictionary = _touches[i]
		if not t.down:
			t.alpha -= delta / FADE_SEC
			if t.alpha <= 0.0:
				gone.append(i)
	for i in gone:
		_touches.erase(i)
	_canvas.update()

func _draw_touches():
	for i in _touches:
		var t: Dictionary = _touches[i]
		var a: float = clamp(t.alpha, 0.0, 1.0)
		var r := SIZE * 0.5 * (1.0 + (1.0 - a) * 0.35) # grows a little as it fades
		if _custom:
			_canvas.draw_texture_rect(_custom, Rect2(t.pos - Vector2(r, r), Vector2(r, r) * 2), false, Color(1, 1, 1, 0.75 * a))
		else:
			_canvas.draw_circle(t.pos, r, Color(1, 1, 1, 0.12 * a))
			_canvas.draw_arc(t.pos, r, 0, TAU, 40, Color(1, 0.86, 0.97, 0.85 * a), 3.0, true)
