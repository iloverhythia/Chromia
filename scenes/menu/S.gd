extends ScrollContainer

# The menu pages' scrolling (Settings, Credits). The mouse wheel glides to
# where it would have jumped (the same distance per notch, eased over a few
# frames), so it isn't chunky. Dragging the scrollbar, touch dragging and
# keyboard focus still move it straight away.

const _SKIP_TYPES := [
	"HSlider", "VSlider", "Slider",
	"HScrollBar", "VScrollBar", "ScrollBar",
]
const SMOOTH_SPEED := 16.0 # higher: catches up faster

var _shown: float = 0.0     # where it is drawn (between frames of a glide)
var _target: float = 0.0    # where the wheel wants it
var _last_set: int = 0      # scroll_vertical as this script last left it
var _gliding := false
var _wheel_frames := 0      # a wheel notch just reached this container

func _set_pass_filter_recursive(node: Node):
	for child in node.get_children():
		if child is Control:
			var is_drag_control := false
			for t in _SKIP_TYPES:
				if child.is_class(t):
					is_drag_control = true
					break
			if not is_drag_control:
				child.mouse_filter = Control.MOUSE_FILTER_PASS
		_set_pass_filter_recursive(child)

func _ready():
	_set_pass_filter_recursive(self)
	_last_set = scroll_vertical
	_shown = scroll_vertical
	_target = scroll_vertical

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and (event.button_index == BUTTON_WHEEL_UP or event.button_index == BUTTON_WHEEL_DOWN):
		_wheel_frames = 2

func _max_scroll() -> float:
	var bar = get_v_scrollbar()
	return max(0.0, bar.max_value - bar.page) if bar != null else 0.0

func _process(delta):
	var cur: int = scroll_vertical
	if cur != _last_set:
		if _wheel_frames > 0:
			# the wheel jumped it: glide there instead (several notches add up)
			_target = clamp(_target + (cur - _last_set), 0.0, _max_scroll())
			_gliding = true
			scroll_vertical = _last_set
		else:
			# moved some other way (scrollbar, touch, focus): follow at once
			_gliding = false
			_shown = cur
			_target = cur
			_last_set = cur
	if _wheel_frames > 0:
		_wheel_frames -= 1
	if _gliding:
		_shown = lerp(_shown, _target, 1.0 - exp(-SMOOTH_SPEED * delta))
		if abs(_target - _shown) < 0.5:
			_shown = _target
			_gliding = false
		scroll_vertical = int(round(_shown))
		_last_set = scroll_vertical
