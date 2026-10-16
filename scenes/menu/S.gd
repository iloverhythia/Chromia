extends ScrollContainer

const _SKIP_TYPES := [
	"HSlider", "VSlider", "Slider",
	"HScrollBar", "VScrollBar", "ScrollBar",
]

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
