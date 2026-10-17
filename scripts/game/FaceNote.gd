extends MeshInstance

export var look_multi = 1.0
export var speed_multi = 1.0

var ok = false
var enabled = false
var _cursor: Spatial = null

func _ready():
	ok = true

func _process(delta):
	if not enabled or not is_visible_in_tree():
		return
	if _cursor == null:
		_cursor = get_parent().get_parent().get_node_or_null("Spawn/Cursor")
	if _cursor:
		var clpos:Vector3
		clpos += (_cursor.translation - clpos) * speed_multi
		look_at(clpos * look_multi,Vector3(0,1,0))
	else:
		pass
