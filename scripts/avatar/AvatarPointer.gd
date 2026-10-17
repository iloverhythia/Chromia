extends Spatial

var _cursor: Spatial = null

func _process(delta):
	if not is_visible_in_tree():
		return
	if _cursor == null:
		_cursor = get_parent().get_parent().get_node_or_null("Spawn/Cursor")
	if _cursor:
		look_at(_cursor.translation - Vector3(2,0,0),Vector3.UP)
	else:
		pass
