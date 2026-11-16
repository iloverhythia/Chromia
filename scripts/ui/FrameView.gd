extends Control

# A frame (FrameDraw.gd) over a round profile picture: put it over the
# picture, the same size (anchors filling it); the frame draws past its
# edges.
#
# A moving frame isn't worked out here for each picture: everyone showing the
# same frame pastes the one picture FrameCache.gd keeps of it (a list of
# thirty players each drawing their own was most of a frame's time). A big
# picture (your profile page) and a picture frame are still drawn directly.

const FrameDraw = preload("res://scripts/ui/FrameDraw.gd")
const FrameCache = preload("res://scripts/ui/FrameCache.gd")
const DIRECT_FROM := 62.0 # px of picture radius: bigger than the cached picture would stay sharp at

var frame := {}
var _acc := 0.0
var _premult: CanvasItemMaterial = null

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

func _radius() -> float:
	return min(rect_size.x, rect_size.y) / 2.0

func _direct() -> bool:
	return _radius() > DIRECT_FROM or String(frame.get("style", "")) == "image"

func _process(delta):
	_acc += delta
	if not is_visible_in_tree():
		return
	if _direct():
		# (drawn here: about 30 times a second while it's on screen)
		if _acc >= 0.033:
			_acc = 0.0
			update()
	elif _acc >= 0.25:
		# (pasted from the shared picture, which moves by itself: it only
		# needs to hear that it's still wanted)
		_acc = 0.0
		FrameCache.instance(get_tree()).touch(frame)

func _draw():
	if frame.empty():
		return
	var r := _radius()
	if r <= 1.0:
		return
	if _direct():
		if material != null:
			material = null
		FrameDraw.draw(self, rect_size / 2.0, r, frame)
		return
	if _premult == null:
		_premult = CanvasItemMaterial.new()
		_premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	if material != _premult:
		material = _premult
	var s := r * FrameDraw.REACH
	draw_texture_rect(FrameCache.instance(get_tree()).texture_for(frame), Rect2(rect_size / 2.0 - Vector2(s, s), Vector2(s, s) * 2.0), false)
