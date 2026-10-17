extends Label

var _t: float = 0.0

# Updating a label re-lays it out, so only refresh the counter 4x a second.
func _process(delta):
	if not is_visible_in_tree():
		return
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	text = String(Engine.get_frames_per_second())
