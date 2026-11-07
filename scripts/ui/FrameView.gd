extends Control

# A frame (FrameDraw.gd) over a round profile picture: put it over the
# picture, the same size (anchors filling it); the frame draws past its
# edges. Redraws about 30 times a second while it's on screen and moving.

const FrameDraw = preload("res://scripts/ui/FrameDraw.gd")

var frame := {}
var _acc := 0.0

func _init():
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_right = 1
	anchor_bottom = 1

# f: the server's frame dictionary (or null / {} for none)
func set_frame(f):
	frame = FrameDraw.parse(f)
	set_process(FrameDraw.animated(frame))
	update()

func _ready():
	set_process(FrameDraw.animated(frame))

func _process(delta):
	_acc += delta
	if _acc < 0.033 or not is_visible_in_tree():
		return
	_acc = 0.0
	update()

func _draw():
	if frame.empty():
		return
	FrameDraw.draw(self, rect_size / 2.0, min(rect_size.x, rect_size.y) / 2.0, frame)
